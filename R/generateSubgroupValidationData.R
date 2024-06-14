race <- list(White = 8527,
             Black = 8516,
             Asian = 8515,
             `AI/AN/HW` = 868557,
             `Unknown Race` = 8552)

ethnicity <- list(Hispanic = 38003563,
                  `Non-Hispanic` = 38003564,
                  `Unknown Ethnicity` = 8552)

gender <- list(Male = 8507, Female = 8532)

CCI_severity <- list(`Severe CCI 5+` = 3, `Moderate CCI 3-4` = 2, `Mild CCI 1-2` = 1, `No comorbidity` = 0)

binary <- list(Yes = 1, No = 0)

targetCohort <- list(All=TRUE)



#' generateSubgroupValidationData
#'
#' Generate cohort subgroup validation data for the already run PLP model
#'
#' @param connectionDetails   connectionDetails object to be connected to the CDM database.
#' @param plpValidationRds    the rds file associated with the PLP model that has been run on the whole target cohort.
#' @param evaluationType      It can be one of the following items: Test or weakRecalibration.
#' @param subgroupCohortInfo
#' @return  a list of three tables including PLP subgroup validation table, subgroup performance metrics table, subgroup calibration summary table.
#' @export
generateSubgroupValidationData <- function(connectionDetails, plpValidationRds, evaluationType, subgroupCohortInfo){

  plpValidationResult <- readRDS(plpValidationRds)$prediction[c('subjectId', 'ageYear', 'gender', 'outcomeCount', 'value', 'evaluationType')]
  plpValidationResult <- plpValidationResult[plpValidationResult$evaluationType == evaluationType,][c('subjectId', 'ageYear', 'gender', 'outcomeCount', 'value')]

  if(nrow(plpValidationResult) < 1){
    stop(sprintf("PLP validation object in RDS file is empty for evaluation type %s!", evaluationType))
  }

  subgroup <- getCohortRaceEthnicity(cdmInfo = cdmInfo, connectionDetails = connectionDetails)
  plpValidationResult <- plpValidationResult %>%
    dplyr::left_join(subgroup, by = c('subjectId' = 'PERSON_ID'))
  names(plpValidationResult)[names(plpValidationResult) == 'RACE'] <- 'race'
  names(plpValidationResult)[names(plpValidationResult) == 'ETHNICITY'] <- 'ethnicity'

  print(sprintf('# of recods with NA value: %d',nrow(plpValidationResult[!complete.cases(plpValidationResult), ])))
  print(sprintf('# of recods with NA prediction : %d',nrow(plpValidationResult[is.na(plpValidationResult$value), ])))

  plpValidationResult["race"][is.na(plpValidationResult["race"]) | plpValidationResult["race"] == 0 ] <- 8552
  plpValidationResult["race"][plpValidationResult["race"] == 8657 | plpValidationResult["race"] == 8557 ] <- 868557
  plpValidationResult["ethnicity"][is.na(plpValidationResult["ethnicity"]) | plpValidationResult["ethnicity"] == 0 ] <- 8552


  # Extracting charlson index for target cohort subjects from DB
  subgroup <- getCharlsonData(cdmInfo = cdmInfo, connectionDetails = connectionDetails)
  plpValidationResult <- plpValidationResult %>%
    dplyr::left_join(subgroup, by = c('subjectId' = 'SUBJECT_ID'))
  names(plpValidationResult)[names(plpValidationResult) == 'SCORE'] <- 'charlsonIndex'
  print(sprintf('# of recods with NA CCI score: %d',nrow(plpValidationResult[is.na(plpValidationResult$charlsonIndex), ])))
  print(sprintf('# of recods with 0 CCI score prediction: %d',nrow(plpValidationResult[plpValidationResult$charlsonIndex == 0 & !is.na(plpValidationResult$charlsonIndex), ])))
  print(table(plpValidationResult$charlsonIndex))

  plpValidationResult["charlsonIndex"][is.na(plpValidationResult["charlsonIndex"])] <- 0
  plpValidationResult["charlsonIndex"][plpValidationResult["charlsonIndex"] > 6 ] <- 7
  print(table(plpValidationResult$charlsonIndex))

  names(plpValidationResult)[names(plpValidationResult) == 'charlsonIndex'] <- 'CCI_score'

  plpValidationResult["CCI_severity"] <- plpValidationResult["CCI_score"]

  plpValidationResult["CCI_severity"][plpValidationResult["CCI_score"] >= 1 & plpValidationResult["CCI_score"] <= 2] <- 1
  plpValidationResult["CCI_severity"][plpValidationResult["CCI_score"] >= 3 & plpValidationResult["CCI_score"] <= 4] <- 2
  plpValidationResult["CCI_severity"][plpValidationResult["CCI_score"] >= 5] <- 3

  print(table(plpValidationResult["CCI_severity"]))


  # Loading subgroup subjects from DB
  for (s in subgroupCohortInfo) {
    subgroup <- getSubCohortFromDb(subCohortId = s$id, cdmInfo = cdmInfo, connectionDetails = connectionDetails)
    plpValidationResult <- plpValidationResult %>%
      dplyr::left_join(subgroup, by = c('subjectId' = 'SUBJECT_ID'))
    names(plpValidationResult)[names(plpValidationResult) == 'SUBGROUP_FLAG'] <- s$name
    plpValidationResult[s$name][is.na(plpValidationResult[s$name])] <- 0
  }

  validationTable <- data.frame(Subgroup=character(),
                                CohortCount=double(),
                                Outcome=double(),
                                Incidence=double(),
                                AUROC=double(),
                                AUROC_Low=double(),
                                AUROC_High=double(),
                                AUROC_CI=character(),
                                AUPRC=double(),
                                AUPRC_Low=double(),
                                AUPRC_High=double(),
                                AUPRC_CI=character()
  )
  print("subgroup performnace metrics are calculating ... ")
  validationTable <- calculateAucValues(plpValidationResult, subgroupList = targetCohort, subgroupName = 'target cohort', resultTable = validationTable)
  validationTable <- calculateAucValues(plpValidationResult, subgroupList = gender, subgroupName = 'gender', resultTable = validationTable)
  validationTable <- calculateAucValues(plpValidationResult, subgroupList = race, subgroupName = 'race', resultTable = validationTable)
  validationTable <- calculateAucValues(plpValidationResult, subgroupList = ethnicity, subgroupName = 'ethnicity', resultTable = validationTable)
  for (s in subgroupCohortInfo) {
    validationTable <- calculateAucValues(plpValidationResult, subgroupList = binary, subgroupName = s$name, resultTable = validationTable)
  }
  validationTable <- calculateAucValues(plpValidationResult, subgroupList = CCI_severity, subgroupName = 'CCI_severity', resultTable = validationTable)

  calibrationSummaryTable <- generateSubgroupCalibrationSummary(plpValidationResult = plpValidationResult, subgroupCohortInfo = subgroupCohortInfo)
  calibrationSummaryTable <- calibrationSummaryTable[c(-2,-3)]
  return(list(plpValidationResult=plpValidationResult, validationTable = validationTable, calibrationSummaryTable = calibrationSummaryTable))
}


getCohortRaceEthnicity <- function(cdmInfo, connectionDetails){
  sqlQuery <- 'select p.person_id, p.race_concept_id as race, p.ethnicity_concept_id as ethnicity
               from (select * from @target_database_schema.@target_cohort_table where cohort_definition_id = @target_cohort_id) coh
               left join @cdm_database_schema.person p
               on coh.subject_id = p.person_id
              '
  renderedSql <- SqlRender::render(
    sql = sqlQuery,
    cdm_database_schema = cdmInfo$cdmDatabaseSchema,
    target_database_schema = cdmInfo$targetDatabaseSchema,
    target_cohort_table = cdmInfo$cohortTable,
    target_cohort_id = cdmInfo$trargetCohortId
  )
  sql <- SqlRender::translate(renderedSql, targetDialect = cdmInfo$dbms)
  connection <- DatabaseConnector::connect(connectionDetails)
  print("Race and ethnicity data is generating ...")
  res <- DatabaseConnector::querySql(connection, sql)

  DatabaseConnector::disconnect(connection = connection)
  return(res)
}


# Create and return Charlson index scores for all target cohort patients
getCharlsonData <- function(cdmInfo, connectionDetails){
  sql_file <- system.file("sql", "charlson-index.sql", package = "FairGenEval")
  sqlQuery <- SqlRender::readSql(sql_file)

  renderedSql <- SqlRender::render(
    sql = sqlQuery,
    cdm_database_schema = cdmInfo$cdmDatabaseSchema,
    target_database_schema = cdmInfo$targetDatabaseSchema,
    target_cohort_table = cdmInfo$cohortTable,
    cohort_definition_id = cdmInfo$trargetCohortId
  )

  sql <- SqlRender::translate(renderedSql, targetDialect = cdmInfo$dbms)

  connection <- DatabaseConnector::connect(connectionDetails)

  # print("Charlson index data is generating ...")
  # DatabaseConnector::executeSql(connection, sql)
  # print("Charlson index data was generated!")

  sqlQuery <- '
                select *
                from @target_database_schema.charlson_data;
              '

  renderedSql <- SqlRender::render(
    sql = sqlQuery,
    target_database_schema = cdmInfo$targetDatabaseSchema
  )
  sql <- SqlRender::translate(renderedSql, targetDialect = cdmInfo$dbms)

  print("Loading Charlson index data from db ...")
  res <- DatabaseConnector::querySql(connection, sql)

  DatabaseConnector::disconnect(connection = connection)

  return(res)
}


getSubCohortFromDb <- function(subCohortId, cdmInfo, connectionDetails){

  sqlQuery <- '
                select subject_id, 1 as subgroup_flag
                from @target_database_schema.@target_cohort_table where cohort_definition_id = @sub_cohort_id;
              '

  renderedSql <- SqlRender::render(
    sql = sqlQuery,
    target_database_schema = cdmInfo$targetDatabaseSchema,
    target_cohort_table = cdmInfo$cohortTable,
    sub_cohort_id = subCohortId
  )
  sql <- SqlRender::translate(renderedSql, targetDialect = cdmInfo$dbms)

  connection <- DatabaseConnector::connect(connectionDetails)
  print(sprintf("Loading subcohort %d from db...", subCohortId))
  res <- DatabaseConnector::querySql(connection, sql)

  DatabaseConnector::disconnect(connection = connection)
  return(res)
}



generateSubgroupCalibrationSummary <- function(plpValidationResult, subgroupCohortInfo){
  subgroups <- list(gender='gender',
                    race='race',
                    ethnicity='ethnicity',
                    CCI_severity='CCI_severity'
  )
  cols = c('subjectId', 'outcomeCount', 'value')
  calibrationSummary <- getCalibrationSummary(plpValidationResult[cols])
  calibrationSummary$evaluation <- 'all'
  for (name in names(subgroups)) {
    tempList <- eval(parse(text=name))
    for (item in tempList) {
      subSummary <- getCalibrationSummary(plpValidationResult[plpValidationResult[subgroups[[name]]] == item,][cols])
      subSummary$evaluation <- paste0(name, '#', item)
      calibrationSummary <- rbind(calibrationSummary, subSummary)
    }
  }

  for (s in subgroupCohortInfo){
    for (i in 0:1){
      subSummary <- getCalibrationSummary(plpValidationResult[plpValidationResult[s$name] == i,][cols])
      subSummary$evaluation <- paste0(s$name, '#', i)
      calibrationSummary <- rbind(calibrationSummary, subSummary)
    }
  }

  return(calibrationSummary)
}



getCalibrationSummary <- function(plpPrediction, thresholdCount = 100){
  q <- unique(stats::quantile(plpPrediction$value, (1:(thresholdCount - 1))/thresholdCount))
  plpPrediction$predictionThresholdId <- cut(plpPrediction$value,
                                             breaks = unique(c(-0.00001, q, max(plpPrediction$value))),
                                             labels = FALSE)

  plpPrediction <- merge(plpPrediction,
                         data.frame(predictionThresholdId=1:(length(q)+1), predictionThreshold=c(0, q)),
                         by='predictionThresholdId', all.x=T)

  # count the number of persons
  PersonCountAtRisk <- stats::aggregate(subjectId ~ predictionThreshold, data = plpPrediction, length)
  names(PersonCountAtRisk)[2] <- "PersonCountAtRisk"

  # count the number of persons in T also in O at time-at-risk
  PersonCountWithOutcome <- stats::aggregate(outcomeCount ~ predictionThreshold, data = plpPrediction, sum)
  names(PersonCountWithOutcome)[2] <- "PersonCountWithOutcome"

  calibrationSummary <- merge(PersonCountAtRisk, PersonCountWithOutcome)

  # Select all persons within the predictionThreshold, compute their average predicted probability
  averagePredictedProbability <- stats::aggregate(plpPrediction$value, list(plpPrediction$predictionThreshold), mean)
  colnames(averagePredictedProbability) <- c('predictionThreshold', 'averagePredictedProbability')
  calibrationSummary <- merge(calibrationSummary, averagePredictedProbability)

  calibrationSummary$observedIncidence <- calibrationSummary$PersonCountWithOutcome/calibrationSummary$PersonCountAtRisk

  return(data.frame(calibrationSummary))
}


aucpr_ci_expit <- function(estimate, num.pos, num.neg, conf.level=0.95) {
  ## https://forums.ohdsi.org/t/confidence-intervals-for-precision-recall-curve/14739/2
  ## Calculates confidence interval for an AUCPR estimate using expit.

  ## convert to logit scale
  est.logit = log(estimate/(1-estimate))
  ## standard error (from Kevin Eng)
  se.logit = sqrt(estimate*(1-estimate)/num.pos)*(1/estimate + 1/(1-estimate))
  ## confidence interval in logit
  ci.logit = est.logit+qnorm(c((1-conf.level)/2,(1+conf.level)/2))*se.logit

  ## back to original scale
  ci = exp(ci.logit)/(1+exp(ci.logit))
  attr(ci,"conf.level") = conf.level
  attr(ci,"method") = "expit"
  return(ci)
}

calculateAucValues <- function(plpValidationResult, subgroupList, subgroupName, resultTable){
  resultTable[nrow(resultTable) + 1,] <- list(toupper(subgroupName), NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA)
  for (item in names(subgroupList)){
    # removes unknown race and ethnicity from results
    if (startsWith(item, 'Unknown')){
      next
    }

    if (item == 'All'){
      subgroupPrediction <- plpValidationResult
    } else {
      subgroupPrediction <- plpValidationResult[!is.na(plpValidationResult[subgroupName]) & plpValidationResult[subgroupName]==subgroupList[item],]
    }

    if(nrow(subgroupPrediction) == 0){
      resultTable[nrow(resultTable) + 1,] <- list(item, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA)
    } else {
      truth <- subgroupPrediction$outcomeCount
      prediction <- subgroupPrediction$value

      #rocObject = pROC::roc(truth, prediction)
      #aucRoc <- pROC::ci.auc(rocObject)

      auc <- pROC::auc(as.factor(truth), prediction, direction="<", quiet=TRUE)
      aucRoc <-pROC::ci(auc)

      positive <- subgroupPrediction$value[subgroupPrediction$outcomeCount == 1]
      negative <- subgroupPrediction$value[subgroupPrediction$outcomeCount == 0]
      pr <- PRROC::pr.curve(scores.class0 = positive, scores.class1 = negative)
      auprc <- pr$auc.integral

      auprc_ci <- aucpr_ci_expit(estimate=auprc, num.pos=length(positive), num.neg=length(negative))
      resultTable[nrow(resultTable) + 1,] <- list(item,
                                                  nrow(subgroupPrediction),
                                                  length(positive),
                                                  round(length(positive)/nrow(subgroupPrediction)*100, digits = 2),
                                                  round(aucRoc[2], digits = 4),
                                                  round(aucRoc[1], digits = 4),
                                                  round(aucRoc[3], digits = 4),
                                                  paste0(round(aucRoc[2], digits = 4),
                                                         ' (', round(aucRoc[1], digits = 4),
                                                         '-', round(aucRoc[3], digits = 4),
                                                         ')'),
                                                  round(auprc, digits = 4),
                                                  round(auprc_ci[1], digits = 4),
                                                  round(auprc_ci[2], digits = 4),
                                                  paste0(round(auprc, digits = 4),
                                                         ' (', round(auprc_ci[1], digits = 4),
                                                         '-', round(auprc_ci[2], digits = 4),
                                                         ')')
      )
    }

  }
  return (resultTable)
}
