# Identify tumor microenviroment pattern
library(SingleCellExperiment)
library(survival)
library(survminer)

library(pheatmap)
library(ggrepel)

library(dplyr)
library(tidyverse)

source("./spatial_analysis_functions.r")
source("./structural_analysis_functions.r")

sce <- readRDS("/mnt/data/lyx/IMC/analysis/allsce.rds")
names(table(sce$Tissue))

savePath <- "/mnt/data/lyx/IMC/analysis/structure/"

tissues <- c("IM", "CT", "TAT")

NeigoborDomain <- c("CNP5", "CNP10", "CNP15", "CNP20", "CNP25", "CNP30")

## Bind CNPs
scimapResult <- read.csv(paste0("/mnt/data/lyx/IMC/analysis/structure/cellular_neighbor_", "All", ".csv"))
scimapResult <- scimapResult[, -1]

sce <- BindResult(sce, scimapResult, NeigoborDomain)

## Plot the CNP contribution

for (structure in NeigoborDomain) {
    savePath2 <- paste0(savePath, structure, "/")
    if (!dir.exists(savePath2)) {
        dir.create(savePath2, recursive = T)
    }

    ## Cell subtype fraction in cellular neighbors pattern
    HeatmapForCelltypeInNeighbor(sce, "SubType", structure, savePath2)

    ## Compare the CNP between tissue
    BarPlotForCelltypeCounts(sce = sce, tissueCol = "Tissue", groupCol = "RFS_status", typeCol = structure, savePath = savePath2)
}

k <- 10

for (tissue in tissues) {
    ## Select tissue
    sce_ <- sce[, sce$Tissue == tissue]
    celltypes <- names(table(sce_$SubType))
    celltypes <- celltypes[celltypes != "UNKNOWN"]

    savePath2 <- paste0(savePath, tissue, "/")

    ## Bind CNPs
    # scimapResult <- read.csv(paste0("/mnt/data/lyx/IMC/analysis/structure/cellular_neighbor_", tissue, ".csv"))
    # scimapResult <- scimapResult[, -1]

    # sce_ <- BindResult(sce_, scimapResult, NeigoborDomain)

    ## Cellular neighbors analysis in different domain size
    for (structure in NeigoborDomain) {
        ## savepath
        savePath3 <- paste0(savePath2, structure, "/")
        if (!dir.exists(savePath3)) {
            dir.create(savePath3, recursive = T)
        }

        ## Cell subtype fraction in cellular neighbors pattern
        # HeatmapForCelltypeInNeighbor(sce_, "SubType", structure, savePath3)

        ## Cellular pattern difference in whole ROI between Relaps and Non-Relaps
        # CompareCellularPattern(sce_, sep = "RFS_status", countcol = structure, n_cluster = 10, clinicalFeatures = NULL, savePath = savePath3)

        ## Celllular neighborhood pattern survival analysis
        CNP_countsDF <- GetAbundance(sce_, countcol = structure, clinicalFeatures = c("RFS_status", "RFS_time"), is.fraction = TRUE, is.reuturnMeans = T)
        CNPs <- names(table(colData(sce_)[, structure]))
        if (!dir.exists(paste0(savePath3, "KM/"))) {
            dir.create(paste0(savePath3, "KM/"), recursive = T)
        }
        for (CNP in CNPs) {
            plotdf <- CNP_countsDF[, c(CNP, "RFS_status", "RFS_time")]
            KMForCNP(plotdf, CNP, savePath = paste0(savePath3, "KM/", "Cellular Neighborhood pattern Suvival analysis of ", CNP, ".pdf"))
        }

        ## Cellular pattern difference in certain central type between relapse and non relapse
        meta <- colData(sce_)

        meta_ <- meta[, match(c("ID", structure, "SubType", "RFS_status"), colnames(meta))]
        meta_ <- as.data.frame(meta_)
        colnames(meta_) <- c("ID", "CNP", "CentralType", "RFS_status")

        df_fraction <- meta_ %>%
            group_by(ID, CentralType, RFS_status, CNP) %>%
            summarise(count = n()) %>%
            mutate(fraction = count / sum(count)) %>%
            select(-count)

        # Reshape the dataframe
        df_wide <- df_fraction %>%
            pivot_wider(names_from = CNP, values_from = fraction, values_fill = 0)

        visuaDF <- as.data.frame(matrix(data = 0, nrow = 0, ncol = 5))

        for (celltype in celltypes) {
            df_wideTemp <- df_wide[df_wide$CentralType %in% celltype, ]
            mat <- df_wideTemp[, c(4:13, 3)]
            mat <- as.data.frame(mat)
            xCol <- c(1, k)
            yCol <- k + 1
            mat_foldchangeMat <- FCandPvalueCal(mat, xCol = xCol, yCol = yCol)
            mat_foldchangeMat$Q.value <- p.adjust(mat_foldchangeMat$P.value, method = "BH")
            mat_foldchangeMat <- cbind(rep(celltype, nrow(mat_foldchangeMat)), mat_foldchangeMat)

            visuaDF <- rbind(visuaDF, mat_foldchangeMat)
        }

        ### Visualize
        if (T) {
            colnames(visuaDF) <- c("CentralType", "CNP", "FC", "P.value", "Q.value")
            visuaDF$FC <- as.numeric(visuaDF$FC)
            visuaDF$P.value <- as.numeric(visuaDF$P.value)
            visuaDF$Q.value <- as.numeric(visuaDF$Q.value)

            visuaDF$dir <- ""
            FC_threshold <- 1.5
            Q_threshold <- 0.05

            for (i in 1:nrow(visuaDF)) {
                if ((visuaDF[i, "FC"] >= FC_threshold) & (visuaDF[i, "Q.value"] <= Q_threshold)) {
                    visuaDF$dir[i] <- "up-regulated"
                }
                if ((visuaDF[i, "FC"] <= (1 / FC_threshold)) & (visuaDF[i, "Q.value"] <= Q_threshold)) {
                    visuaDF$dir[i] <- "down-regulated"
                }
            }

            visuaDF$label <- ifelse(visuaDF$dir != "", visuaDF$CNP, "")

            mycol <- c(ggsci::pal_npg("nrc", alpha = 0.8)(2), "gray")
            names(mycol) <- c("up-regulated", "down-regulated", "NOT")

            visuaDF$log2FC <- log2(visuaDF$FC)

            p1 <- ggplot(visuaDF, aes(x = CentralType, y = log2FC)) +
                geom_jitter(aes(x = CentralType, y = log2FC, color = dir), size = 0.2, width = 0.3) +
                theme_classic() +
                geom_text_repel(aes(label = label), size = 3) +
                scale_color_manual(values = mycol) +
                ylab("log2FC") +
                theme(
                    legend.position = "none",
                    panel.border = element_blank(),
                    panel.grid.major = element_blank(),
                    panel.grid.minor = element_blank(),
                    axis.line = element_line(size = 0.5, colour = "black"),
                    axis.text.x = element_text(colour = "black", angle = 90, hjust = 1, vjust = 0.5),
                    axis.text.y = element_text(colour = "black"),
                    axis.ticks = element_line(colour = "black"),
                    axis.title.y = element_text(size = 10),
                    plot.title = element_text(size = 10, hjust = 0.5)
                )

            pdf(paste0(savePath3, "CNP Difference of Central types between Relapse.pdf"), width = 8, height = 6)
            print(p1)
            dev.off()
        }

        ## Save CNP for final model construction
        if (F) {
            clinicalFeatures <- c(NULL)
            CNP_countsDF <- GetAbundance(sce_, countcol = structure, clinicalFeatures = clinicalFeatures, is.fraction = T, is.reuturnMeans = T)
            write.table(CNP_countsDF, "CNP Abundance for model construction.csv", sep = ",", row.names = T, col.names = T)
        }

        ## Plot CNP on image
        if (F) {
            SavePath1 <- paste0(savePath3, "CNP_oncells/")
            if (!dir.exists(SavePath1)) {
                dir.create(SavePath1, recursive = T)
            }
            colData(sce)[, structure] <- as.factor(colData(sce)[, structure])

            ROIs <- names(table(colData(sce)$ID))
            for (ROI in ROIs) {
                PlotCelltypes(sce, ROI, TypeCol = structure, SavePath = paste0(SavePath1, ROI, "_"))
            }
        }
    }
}

## TME archetype analysis
if (F) {
    ## load clinical information
    GroupInfo <- load_clinical(sce = sce, clinicalFilePath = "/mnt/data/lyx/IMC/clinical.csv")
    ## merge celltype abundance into a dataframe
    AbundanceDF <- MergeAbundanceResult(sce, return.fraction = T)

    selectCelltypes <- c("DPT", "Mono_CLEC9A", "Macro_Multi", "Macro_CD11b", "SC_Vimentin", "TC_Ki67") ## results from abundance analysis volcano plot

    celltypes <- names(table(sce$SubType))
    celltypes <- celltypes[!celltypes %in% selectCelltypes]

    ## cluster patients
    distMat <- dist(t(AbundanceDF[selectCelltypes, ]), method = "euclidean")
    colclust <- hclust(distMat, method = "complete")

    k <- 15
    TMEClusterID <- cutree(colclust, k = k)
    table(TMEClusterID)

    ## column annotation bar
    plotDF <- AbundanceDF[c(selectCelltypes, celltypes), ]

    annotationCol <- matrix(data = NA, nrow = ncol(plotDF), ncol = 3)
    annotationCol <- as.data.frame(annotationCol)

    rownames(annotationCol) <- colnames(plotDF)
    colnames(annotationCol) <- c("TME Archetypes", "RFSS", "KRAS Mutation")

    annotationCol$`TME Archetypes` <- as.factor(as.numeric(TMEClusterID))
    annotationCol$RFSS <- ifelse(GroupInfo$RFS_status == 1, "Relaps", "Non-Relaps")
    annotationCol$`KRAS Mutation` <- ifelse(GroupInfo$KRAS_mutation == 1, "Mutate", "WT")
    # annotationCol$`CRC Site` <- ifelse(GroupInfo$CRC_site == 1, "Right Colon", ifelse(GroupInfo$CRC_site == 2, "Left Colon", "Rectum"))

    p <- pheatmap(plotDF,
        scale = "column", gaps_row = length(selectCelltypes), cutree_cols = k,
        annotation_col = annotationCol, annotation_legend = TRUE,
        cluster_rows = FALSE, cluster_cols = colclust, clustering_distance_cols = "euclidean", clustering_method = "complete",
        show_rownames = TRUE, show_colnames = TRUE, fontsize_col = 6, fontsize_row = 6,
        color = colorRampPalette(c("navy", "white", "firebrick3"))(50),
        angle_col = "270", cellwidth = 6, cellheight = 6
    )
    pdf("/mnt/data/lyx/IMC/analysis/spatial/TME Archetypes.pdf", height = 5, width = 16)
    print(p)
    dev.off()

    ## Assign TME Archetypes label (Voting)
    PlaeblDF <- as.data.frame(TMEClusterID)
    PlaeblDF$PID <- sapply(rownames(PlaeblDF), function(x) {
        strsplit(x, "_")[[1]][1]
    })
    PIDs <- names(table(PlaeblDF$PID))

    label <- c()
    for (i in PIDs) {
        PlaeblDFTemp <- subset(PlaeblDF, PID == i)
        label <- c(label, names(table(PlaeblDFTemp$TMEClusterID))[1])
    }
    names(label) <- PIDs

    ## survival analysis
    label <- as.data.frame(label)
    label$RFS_time <- GroupInfo$RFS_time[match(rownames(label), GroupInfo$PID)]
    label$RFS_status <- GroupInfo$RFS_status[match(rownames(label), GroupInfo$PID)]
    label <- label[-match("W21", rownames(label)), ]

    km <- survfit(Surv(RFS_time, RFS_status) ~ label, data = label)
    p <- ggsurvplot(km,
        data = label,
        linetype = c("solid", "solid"),
        surv.median.line = "hv", surv.scale = "percent",
        pval = T, risk.table = T,
        conf.int = T, conf.int.alpha = 0.1, conf.int.style = "ribbon",
        risk.table.y.text = T,
        palette = c("#3300CC", "#CC3300"),
        xlab = "Recurrence time"
    )

    pdf("/mnt/data/lyx/IMC/analysis/spatial/TME archetypes survival analysis.pdf", width = 8, height = 6)
    print(p)
    dev.off()

    ## visualize TME archetypes
    savePath <- "/mnt/data/lyx/IMC/analysis/spatial/archetypes/"
    if (!dir.exists(savePath)) {
        dir.create(savePath)
    }
    ROIs <- names(table(sce$ID))
    for (ROI in ROIs) {
        PlotCelltypes(sce, ROI, selectCelltypes, SavePath = paste0(savePath, ROI, " TME archetypes.pdf"))
    }
}
