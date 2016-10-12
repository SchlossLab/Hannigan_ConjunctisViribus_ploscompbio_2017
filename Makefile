# Makefile
# Hannigan-2016-ConjunctisViribus
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

#########################
# Set General Variables #
#########################
ACCLIST := $(shell awk '{ print "data/ViromePublications/"$$7 }' ./data/PublishedDatasets/SutdyInformation.tsv)
SAMPLELIST := $(shell awk '{ print $$3 }' ./data/PublishedDatasets/metadatatable.tsv | sort | uniq)

# For debugging right now
print:
	echo ${SAMPLELIST}



#############
# Set Rules #
#############
contigs: ${SAMPLELIST}



####################
# Model Validation #
####################
VALDIR=./data/ValidationSet

# Get the sequences to use in this analysis
${VALDIR}/ValidationPhageNoBlock.fa \
${VALDIR}/ValidationBacteriaNoBlock.fa : \
			${VALDIR}/PhageID.tsv \
			${VALDIR}/BacteriaID.tsv
	bash ./bin/GetValidationSequences.sh \
		${VALDIR}/PhageID.tsv \
		${VALDIR}/BacteriaID.tsv \
		${VALDIR}/ValidationPhageNoBlock.fa \
		${VALDIR}/ValidationBacteriaNoBlock.fa

# Get the formatted interaction file
${VALDIR}/Interactions.tsv : \
			${VALDIR}/BacteriaID.tsv \
			${VALDIR}/InteractionsRaw.tsv
	Rscript ./bin/MergeForInteractions.R \
		-b ${VALDIR}/BacteriaID.tsv \
		-i ${VALDIR}/InteractionsRaw.tsv \
		-o ${VALDIR}/Interactions.tsv

BSET=./data/BenchmarkingSet

${BSET}/BenchmarkCrisprsFormat.tsv \
${BSET}/BenchmarkProphagesFormatFlip.tsv \
${BSET}/MatchesByBlastxFormatOrder.tsv \
${BSET}/PfamInteractionsFormatScoredFlip.tsv : \
			${VALDIR}/ValidationPhageNoBlock.fa \
			${VALDIR}/ValidationBacteriaNoBlock.fa
	bash ./bin/BenchmarkingModel.sh \
		${VALDIR}/ValidationPhageNoBlock.fa \
		${VALDIR}/ValidationBacteriaNoBlock.fa \
		${BSET}/BenchmarkCrisprsFormat.tsv \
		${BSET}/BenchmarkProphagesFormatFlip.tsv \
		${BSET}/MatchesByBlastxFormatOrder.tsv \
		${BSET}/PfamInteractionsFormatScoredFlip.tsv \
		"BenchmarkingSet"

validationnetwork : \
			${VALDIR}/Interactions.tsv \
			${BSET}/BenchmarkCrisprsFormat.tsv \
			${BSET}/BenchmarkProphagesFormatFlip.tsv \
			${BSET}/PfamInteractionsFormatScoredFlip.tsv \
			${BSET}/MatchesByBlastxFormatOrder.tsv
	rm -r ../../bin/neo4j-enterprise-2.3.0/data/graph.db/
	mkdir ../../bin/neo4j-enterprise-2.3.0/data/graph.db/
	bash ./bin/CreateProteinNetwork \
		${VALDIR}/Interactions.tsv \
		${BSET}/BenchmarkCrisprsFormat.tsv \
		${BSET}/BenchmarkProphagesFormatFlip.tsv \
		${BSET}/PfamInteractionsFormatScoredFlip.tsv \
		${BSET}/MatchesByBlastxFormatOrder.tsv \
		"TRUE"

# Run the R script for the validation ROC curve analysis
./figures/rocCurves.pdf \
./figures/rocCurves.png \
./data/rfinteractionmodel.RData : \
			${VALDIR}/Interactions.tsv \
			${BSET}/BenchmarkCrisprsFormat.tsv \
			${BSET}/BenchmarkProphagesFormatFlip.tsv \
			${BSET}/PfamInteractionsFormatScoredFlip.tsv \
			${BSET}/MatchesByBlastxFormatOrder.tsv
	bash ./bin/RunRocAnalysisWithNeo4j.sh



# ##########################################
# # Download Global Virome Dataset Studies #
# ##########################################
# Download the sequences for the dataset
# Use the list because it allows for test of targets
$(ACCLIST): %: ./data/PublishedDatasets/SutdyInformation.tsv
	echo $@
	bash ./bin/DownloadPublishedVirome.sh \
		$< \
		$@



############################
# Total Dataset Networking #
############################
### CONTIG ASSEMBLY AND QC

# Run quality control as well here
# Need to decompress the fastq files first from SRA
${SAMPLELIST}: %: ./data/ViromePublications ./data/PublishedDatasets/metadatatable.tsv
	echo Makefile is calling to process $@
	bash ./bin/QcAndContigs.sh \
		$@ \
		./data/ViromePublications/ \
		./data/PublishedDatasets/metadatatable.tsv \
		"QualityOutput"

# Merge the contigs into a single file
./data/TotalCatContigsBacteria.fa \
./data/TotalCatContigsPhage.fa \
./data/TotalCatContigs.fa : \
			./data/QualityOutput \
			./data/PublishedDatasets/metadatatable.tsv
	bash ./bin/catcontigs.sh \
		./data/QualityOutput \
		./data/TotalCatContigsBacteria.fa \
		./data/TotalCatContigsPhage.fa \
		./data/PublishedDatasets/metadatatable.tsv \
		./data/TotalCatContigs.fa

# At this point I have two contig files that I need to keep straight
# One for bacteria, one for phage

# Generate a contig relative abundance table
./data/ContigRelAbundForGraph.tsv : \
			./data/TotalCatContigs.fa \
			./data/QualityOutput/raw
	bash ./bin/CreateContigRelAbundTable.sh \
		./data/TotalCatContigs.fa \
		./data/QualityOutput/raw \
		./data/ContigRelAbundForGraph.tsv

# Split abundance table by phage and bacteria samples/contigs
./data/BacteriaContigAbundance.tsv \
./data/PhageContigAbundance.tsv : \
			./data/TotalCatContigsBacteria.fa \
			./data/TotalCatContigsPhage.fa \
			./data/PublishedDatasets/metadatatable.tsv
	bash ./bin/SepAbundanceTable.sh \
		./data/PublishedDatasets/metadatatable.tsv \
		./data/TotalCatContigsBacteria.fa \
		./data/TotalCatContigsPhage.fa \
		./data/BacteriaContigAbundance.tsv \
		./data/PhageContigAbundance.tsv

# Transform contig abundance table for CONCOCT
./data/ContigRelAbundForConcoct.tsv : \
			./data/ContigRelAbundForGraph.tsv
	Rscript ./bin/ReshapeAlignedAbundance.R \
		-i ./data/ContigRelAbundForGraph.tsv \
		-o ./data/ContigRelAbundForConcoct.tsv \
		-p 0.1

# Run CONCOCT to get contig clusters
# Read length is an approximate average from the studies
# Im skipping total coverage because I don't think it makes sense for this dataset
./data/ContigClusters : \
			./data/TotalCatContigs.fa \
			./data/ContigRelAbundForConcoct.tsv
	mkdir ./data/ContigClusters
	concoct \
		--coverage_file ./data/ContigRelAbundForConcoct.tsv \
		--composition_file ./data/TotalCatContigs.fa \
		--clusters 500 \
		--kmer_length 5 \
		--length_threshold 1000 \
		--read_length 150 \
		--basename ./data/ContigClusters/ \
		--no_total_coverage \
		--iterations 50


### CONTIG STATISTICS
PSTAT=./data/PhageContigStats

# Prepare to plot contig stats like sequencing depth, length, and circularity
${PSTAT}/ContigLength.tsv \
${PSTAT}/FinalContigCounts.tsv \
${PSTAT}/circularcontigsFormat.tsv : \
			./data/TotalCatContigs.fa \
			./data/ContigRelAbundForGraph.tsv
	bash ./bin/contigstats.sh \
		./data/TotalCatContigs.fa \
		./data/ContigRelAbundForGraph.tsv \
		${PSTAT}/ContigLength.tsv \
		${PSTAT}/FinalContigCounts.tsv \
		${PSTAT}/circularcontigsFormat.tsv \
		${PSTAT}

# Finalize the contig stats plots
./figures/ContigStats.pdf \
./figures/ContigStats.png : \
			${PSTAT}/ContigLength.tsv \
			${PSTAT}/FinalContigCounts.tsv \
			${PSTAT}/circularcontigsFormat.tsv
	Rscript ./bin/FinalizeContigStats.R \
		-l ${PSTAT}/ContigLength.tsv \
		-c ${PSTAT}/FinalContigCounts.tsv \
		-x ${PSTAT}/circularcontigsFormat.tsv
###


### DRAW PRIMARY NETWORK GRAPH (PHAGE + REFERENCE BACTERA)

VREF=./data/ViromeAgainstReferenceBacteria
# In this case the samples will get run against the bacteria reference genome set
ViromeRefRun : ${VREF}/BenchmarkCrisprsFormat.tsv \
	${VREF}/BenchmarkProphagesFormatFlip.tsv \
	${VREF}/MatchesByBlastxFormatOrder.tsv \
	${VREF}/PfamInteractionsFormatScoredFlip.tsv

${VREF}/BenchmarkCrisprsFormat.tsv \
${VREF}/BenchmarkProphagesFormatFlip.tsv \
${VREF}/MatchesByBlastxFormatOrder.tsv \
${VREF}/PfamInteractionsFormatScoredFlip.tsv : \
			./data/TotalCatContigs.fa \
			${VALDIR}/ValidationBacteriaNoBlock.fa
	bash ./bin/BenchmarkingModel.sh \
		./data/TotalCatContigs.fa \
		${VALDIR}/ValidationBacteriaNoBlock.fa \
		${VREF}/BenchmarkCrisprsFormat.tsv \
		${VREF}/BenchmarkProphagesFormatFlip.tsv \
		${VREF}/MatchesByBlastxFormatOrder.tsv \
		${VREF}/PfamInteractionsFormatScoredFlip.tsv \
		"ViromeAgainstReferenceBacteria"

# Annotate contig IDs with cluster IDs and further compress
clusterrun : ${VREF}/BenchmarkProphagesFormatFlipClustered.tsv \
	${VREF}/MatchesByBlastxFormatOrderClustered.tsv \
	${VREF}/PfamInteractionsFormatScoredFlipClustered.tsv

${VREF}/BenchmarkProphagesFormatFlipClustered.tsv \
${VREF}/MatchesByBlastxFormatOrderClustered.tsv \
${VREF}/PfamInteractionsFormatScoredFlipClustered.tsv : \
			${VREF}/BenchmarkProphagesFormatFlip.tsv \
			${VREF}/MatchesByBlastxFormatOrder.tsv \
			${VREF}/PfamInteractionsFormatScoredFlip.tsv \
			./data/ContigClusters/clustering_gt1000.csv
	bash ./bin/ClusterContigScores.sh \
		${VREF}/BenchmarkProphagesFormatFlip.tsv \
		${VREF}/MatchesByBlastxFormatOrder.tsv \
		${VREF}/PfamInteractionsFormatScoredFlip.tsv \
		${VREF}/BenchmarkProphagesFormatFlipClustered.tsv \
		${VREF}/MatchesByBlastxFormatOrderClustered.tsv \
		${VREF}/PfamInteractionsFormatScoredFlipClustered.tsv \
		./data/ContigClusters/clustering_gt1000.csv \
		"ViromeAgainstReferenceBacteria"

# Make a graph database from the experimental information
expnetwork : \
			${VALDIR}/Interactions.tsv \
			${VREF}/BenchmarkCrisprsFormat.tsv \
			${VREF}/BenchmarkProphagesFormatFlipClustered.tsv \
			${VREF}/PfamInteractionsFormatScoredFlipClustered.tsv \
			${VREF}/MatchesByBlastxFormatOrderClustered.tsv
	# Note that this resets the graph database and erases
	# the validation information we previously added.
	rm -r ../../bin/neo4j-enterprise-2.3.0/data/graph.db/
	mkdir ../../bin/neo4j-enterprise-2.3.0/data/graph.db/
	bash ./bin/CreateProteinNetwork \
		${VALDIR}/Interactions.tsv \
		${VREF}/BenchmarkCrisprsFormat.tsv \
		${VREF}/BenchmarkProphagesFormatFlipClustered.tsv \
		${VREF}/PfamInteractionsFormatScoredFlipClustered.tsv \
		${VREF}/MatchesByBlastxFormatOrderClustered.tsv \
		"FALSE"

# Predict interactions between nodes
./data/PredictedRelationshipTable.tsv : \
			./data/rfinteractionmodel.RData
	bash ./bin/RunPredictionsWithNeo4j.sh \
		./data/rfinteractionmodel.RData \
		./data/PredictedRelationshipTable.tsv

# Add relationships
finalrelationships \
./figures/BacteriaPhageNetworkDiagram.pdf \
./figures/BacteriaPhageNetworkDiagram.png \
./figures/PhageHostHist.pdf \
./figures/PhageHostHist.png \
./figures/BacteriaEdgeCount.pdf \
./figures/BacteriaEdgeCount.png : \
		./data/PredictedRelationshipTable.tsv
	bash ./bin/AddRelationshipsWrapper.sh \
		./data/PredictedRelationshipTable.tsv

# Collapse sequence counts by contig cluster
./data/ContigRelAbundForGraphClustered.tsv : \
			./data/ContigRelAbundForGraph.tsv \
			./data/ContigClusters/clustering_gt1000.csv
	bash ./bin/ClusterContigAbundance.sh \
		./data/ContigRelAbundForGraph.tsv \
		./data/ContigRelAbundForGraphClustered.tsv \
		./data/ContigClusters/clustering_gt1000.csv \
		"ViromeAgainstReferenceBacteria"

# Add metadata to the graph
addmetadata : \
			./data/ContigRelAbundForGraphClustered.tsv \
			./data/PublishedDatasets/metadatatable.tsv
	bash ./bin/AddMetadata.sh \
		./data/ContigRelAbundForGraphClustered.tsv \
		./data/PublishedDatasets/metadatatable.tsv
###
