
# Create a connectionDetails object to be used in the package
# For other dbms with different security methods, the appropriate approach can be used here to create connectionDetails object
dbms = 'bigquery'
driverPath = "/Users/behzadn/SimbaJDBCDriverforGoogleBigQuery42_1.2.22.1026"

connectionString = BQJdbcConnectionStringR::createBQConnectionString(
  projectId = "som-nero-phi-boussard",
  defaultDataset = "bn_porpoise",
  authType = 2,
  jsonCredentialsPath = "/Users/behzadn/.config/gcloud/application_default_credentials.json")

connectionDetails <- DatabaseConnector::createConnectionDetails(dbms=dbms,
                                                                connectionString=connectionString,
                                                                user="",
                                                                password="",
                                                                pathToDriver=driverPath)

# Set the CDM database schema information. The cohort table should be located in the targetDatabaseSchema
cdmInfo <- list(
  vocabularyDatabaseSchema = "`som-rit-phi-starr-prod.starr_omop_cdm5_confidential_lite_2024_06_02`",
  cdmDatabaseSchema = "`som-nero-phi-boussard.bn_porpoise`",
  targetDatabaseSchema = "`som-nero-phi-boussard.bn_porpoise`",
  cohortTable = "cohort_09042023",
  trargetCohortId = 1,
  dbms = 'bigquery'
)

# Set evaluationType to 'Test' for internal validation
# Set evaluation type to 'Validation' for external validation
# Set evaluation type to 'weakRecalibration' for external validation if the model output has been calibrated by weakRecalibration method
evaluationType = "Test"

# Any subgroup population can be manually generated from the target cohort and stored in the cohort table with a separate cohort definition id
# The model will be evaluated for those sub-populations if the list provided. The default value is empty list
# The id corresponds to the cohort definition id in the cohort table
subgroupCohortInfo <- list(list(id =3, name = 'diabetes'), list(id =4, name = 'depression'), list(id =5, name = 'obesity'), list(id =1001, name = 'opioid_exposed'))

# Set the path of the runPlp.rds file
plpValidationRds <- '/Users/behzadn/BoussardLab/NLM-pain/prolonged-opioid-use/project-source-codes/porpoise/PlpMultiOutput-09042023/PlpMultiOutput-Chi2-STARR/Analysis_1/plpResult/runPlp.rds'



# ------------------- Use of the FairGenEval to generate the evaluation plots ------------------

# Calculate AUROC and AUPRC for demographics, charlson comorbidity severity groups and all the clinical subgroups noted above
# It returns the required data for plotting calibration and net-benefits curves, as well as the forest plot
allValidationResults <- FairGenEval::generateSubgroupValidationData(connectionDetails=connectionDetails,
                                                                    plpValidationRds=plpValidationRds,
                                                                    evaluationType = evaluationType,
                                                                    subgroupCohortInfo = subgroupCohortInfo)


plotDir <- '/Users/behzadn/plot'

# ----- Forest plot based AUROC or AUPRC -----------
FairGenEval::generateForestPlot(resultDataFrame=allValidationResults$validationTable, estimateCol='AUROC', outputFile=file.path(plotDir, "forest_auroc.tiff"))
FairGenEval::generateForestPlot(resultDataFrame=allValidationResults$validationTable, estimateCol='AUPRC', outputFile=file.path(plotDir, "forest_auprc.tiff"))
FairGenEval::generateMultiForestPlot(resultDataFrame=allValidationResults$validationTable, outputFile=file.path(plotDir, "forest_auroc_auprc.tiff"))


# ----- Net Benefit plot -----------
FairGenEval::generateNetBenefitPlot(allValidationResults$plpValidationResult, subgroup = "all", outputFile = file.path(plotDir, "nb_all.pdf"))
FairGenEval::generateNetBenefitPlot(allValidationResults$plpValidationResult, subgroup = "diabetes#0", outputFile = file.path(plotDir, "nb_no_diabetes.pdf"))
FairGenEval::generateNetBenefitPlot(allValidationResults$plpValidationResult, subgroup = "diabetes#1", outputFile = file.path(plotDir, "nb_diabetes.pdf"))

FairGenEval::generateNetBenefitPlot(allValidationResults$plpValidationResult, subgroup = "gender#8532", outputFile = file.path(plotDir, "nb_female.pdf"))

# severity#0 corresponds to no-comorbidity, #1 mild, #2 moderate, #3 severe
FairGenEval::generateNetBenefitPlot(allValidationResults$plpValidationResult, subgroup = "CCI_severity#0", outputFile = file.path(plotDir, "nb_no_comorbidity.pdf"))
FairGenEval::generateNetBenefitPlot(allValidationResults$plpValidationResult, subgroup = "CCI_severity#3", outputFile = file.path(plotDir, "nb_sever_comorbidity.pdf"))

# ----- Prediction distribution plot -----------
FairGenEval::generatePredictionDistributionPlot(allValidationResults$plpValidationResult, subgroup = "all", outputFile = file.path(plotDir, "dist_all.pdf"))
FairGenEval::generatePredictionDistributionPlot(allValidationResults$plpValidationResult, subgroup = "gender#8532", outputFile = file.path(plotDir, "dist_female.pdf"))


# ----- Calibration plot -----------
FairGenEval::generateCalibrationPlot(validationResults = allValidationResults, subgroup = "all", outputFile = file.path(plotDir, "calib_all.pdf"))
FairGenEval::generateCalibrationPlot(validationResults = allValidationResults, subgroup = "diabetes#0", outputFile = file.path(plotDir, "calib_no_diabetes.pdf"))
FairGenEval::generateCalibrationPlot(validationResults = allValidationResults, subgroup = "diabetes#1", outputFile = file.path(plotDir, "calib_diabetes.pdf"))
FairGenEval::generateCalibrationPlot(validationResults = allValidationResults, subgroup = "CCI_severity#0", outputFile = file.path(plotDir, "calib_no_comorbidity.pdf"))
FairGenEval::generateCalibrationPlot(validationResults = allValidationResults, subgroup = "CCI_severity#3", outputFile = file.path(plotDir, "calib_sever_comorbidity.pdf"))



