if(NOT DEFINED BIN2C)
  message(FATAL_ERROR "BIN2C is not defined")
endif()
if(NOT DEFINED INPUT_FILE)
  message(FATAL_ERROR "INPUT_FILE is not defined")
endif()
if(NOT DEFINED OUTPUT_FILE)
  message(FATAL_ERROR "OUTPUT_FILE is not defined")
endif()
if(NOT DEFINED VARIABLE_NAME)
  message(FATAL_ERROR "VARIABLE_NAME is not defined")
endif()

execute_process(
  COMMAND "${BIN2C}" --padd 0 --type char --name "${VARIABLE_NAME}" "${INPUT_FILE}"
  OUTPUT_FILE "${OUTPUT_FILE}"
  RESULT_VARIABLE BIN2C_STATUS)

if(NOT BIN2C_STATUS EQUAL 0)
  message(FATAL_ERROR "bin2c failed for ${INPUT_FILE} with status ${BIN2C_STATUS}")
endif()
