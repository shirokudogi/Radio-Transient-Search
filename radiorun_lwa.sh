#!/bin/bash

shopt -s extglob

# User input test patterns.
AFFIRMATIVE='^(y|yes|yup|yea|yeah|ya)$'
INTEGER_NUM='^[+-]?[0-9]+$'
REAL_NUM='^[+-]?[0-9]+([.][0-9]+)?$'

# Configure base run parameters.
NUM_PROCS=$(nproc --all)   # Number of processes to use in the MPI environment.
MEM_LIMIT=32768            # Memory limit, in MBs, for creating waterfall tiles in memory.

INSTALL_DIR="${HOME}/local/radiotrans"
DEFAULT_DEBUG=0
SKIPMOVE_OPT=


# Select whether we are using the release install of radiotrans or still using the developer version to
# debug issues.
if [[ ${#} -gt 0 ]]; then
   while [ -n "${1}" ]
   do
      case "${1}" in
         --DEBUG) # Force enable default debugging configuration.
            echo "radiorun_lwa.sh: Force enabling default debugging configuration."
            DATA_DIR="/data/network/recent_data/jtsai"
            DATA_FILENAME="057974_001488582"
            DATA_PATH="${DATA_DIR}/${DATA_FILENAME}"
            LABEL="GWRDEBUG"
            INSTALL_DIR="${HOME}/dev/radiotrans"
            WORK_DIR="/mnt/toaster/cyancey/${LABEL}"
            RESULTS_DIR="${HOME}/analysis/${LABEL}"
            #INTEGTIME="6.89633"
            INTEGTIME="2089.80"
            DEFAULT_DEBUG=1
            #DECIMATION=30000
            DECIMATION=4000
            SKIPMOVE_OPT="--skip-transfer"
            shift
            ;;
         -I | --install-dir) # Set the install directory to the specified location.
            if [ ${DEFAULT_DEBUG} -eq 0]; then
               if [ -z "${INSTALL_DIR}" -a -d "${2}" ]; then
                  INSTALL_DIR="${2}"
               else
                  echo "Cannot find install directory ${2}"
               fi
            else
               echo "Install directory ignored.  Forced to default debug configuration."
               echo "INSTALL_DIR = ${INSTALL_DIR}"
            fi
            shift; shift
            ;;
         -R | --results-dir) # Set the results directory to the specified location.
            if [ ${DEFAULT_DEBUG} -eq 0]; then
               if [ -z "${RESULTS_DIR}" -a -d "${2}" ]; then
                  RESULTS_DIR="${2}"
               else
                  echo "Cannot find results directory ${2}"
               fi
            else
               echo "Results directory ignored.  Forced to default debug configuration."
               echo "RESULTS_DIR = ${RESULTS_DIR}"
            fi
            shift; shift
            ;;
         -W | --work-dir) # Set the working directory to the specified location.
            if [ ${DEFAULT_DEBUG} -eq 0 ]; then
               if [ -z "${WORK_DIR}" -a -d "${2}" ]; then
                  WORK_DIR="${2}"
               else
                  echo "Cannot find install directory ${2}"
               fi
            fi
            shift; shift
            ;;
         -F | --data-file) # Set the radio data file to the specified path.
            if [ ${DEFAULT_DEBUG} -eq 0 ]; then
               if [ -z "${DATA_PATH}" -a -f "${2}" ]; then
                  DATA_PATH="${2}"
               else
                  echo "Cannont find radio data file ${2}"
               fi
            fi
            shift; shift
            ;;
         -T | --integrate-time) # Specify the integration time.
            if [ ${DEFAULT_DEBUG} -eq 0 ]; then
               if [ -z "${INTEGTIME}" ]; then
                  if [[ "${2}" =~ ${REAL_NUM} ]]; then
                     if [ ${2} -gt 0 ]; then
                        INTEGTIME="${2}"
                     fi
                  fi
               fi
            fi
            shift; shift
            ;;
         -L | --label) # Specify a label for the run.
            if [ ${DEFAULT_DEBUG} -eq 0 ]; then
               if [ -z "${LABEL}" ]; then
                  LABEL="${2}"
               fi
            fi
            shift; shift
            ;;
         -C | --config-file) # Specify path for the common configuration file.
            if [ -z "${COMMCONFIG_FILE}" ]; then
               # Just in case the user gives a full path, strip off the directory component.  We just
               # need a name.
               COMMCONFIG_FILE=$(basename "${2}")
            fi
            shift; shift
            ;;
         -S | --small-node) # Lower the memory limit for the smaller nodes (ones having 32 GB total RAM)
                            # LWA.
            MEM_LIMIT=16384
            shift
            ;;
         -E | --enable-hann) # Enable Hann windowing on the time-series data.
            ENABLE_HANN="--enable-hann"
            shift
            ;;
         -D | --decimation) # Specify the coarse spectrogram decimation.
            if [ ${DEFAULT_DEBUG} -eq 0 ]; then
               if [ -z "${DECIMATION}" ]; then
                  if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                     if [ ${2} -gt 0 ]; then
                        DECIMATION="${2}"
                     fi
                  fi
               fi
            fi
            shift; shift
            ;;
         --skip-transfer) # Skip transfer of results files to the results directory.
            SKIPMOVE_OPT="--skip-transfer"
            shift
            ;;
         *) # Ignore anything else.
            shift
            ;;
      esac
   done
fi

# Create the working directory, if it doesn't exist.
if [ -z "${WORK_DIR}" ]; then
   WORK_DIR="/mnt/toaster/${USER}"
   if [ -n "${LABEL}" ]; then
      WORK_DIR="${WORK_DIR}/${LABEL}"
   fi
fi
if [ ! -d "${WORK_DIR}" ]; then
   mkdir "${WORK_DIR}"
   if [ ! -d "${WORK_DIR}" ]; then
      echo "Could not create working directory ${WORK_DIR}"
      exit 1
   fi
fi

# Create the results directory, if it doesn't exist.
if [ -z "${RESULTS_DIR}" ]; then
   RESULTS_DIR="${HOME}/analysis"
   if [ -n "${LABEL}" ]; then
      RESULTS_DIR="${RESULTS_DIR}/${LABEL}"
   else
      RESULTS_DIR="${RESULTS_DIR}/GWR_RESULTS"
   fi
fi
if [ ! -d "${RESULTS_DIR}" ]; then
   mkdir "${RESULTS_DIR}"
   if [ ! -d "${RESULTS_DIR}" ]; then
      echo "Could not create results directory ${RESULTS_DIR}"
      exit 1
   fi
fi

# Set the common configuration file path
if [ -z "${COMMCONFIG_FILE}" ]; then
   COMMCONFIG_FILE="radiotrans.ini"
fi

# Build the command-line to run radiotrans.sh
CMD="${INSTALL_DIR}/radioreduce.sh"
CMD_OPTS=(--install-dir "${INSTALL_DIR}" --integrate-time ${INTEGTIME} \
      --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} ${ENABLE_HANN} \
      --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
      --decimation ${DECIMATION} \
      --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${SKIPMOVE_OPT})

# Run the radiotrans.sh script.
${CMD} ${CMD_OPTS[*]} "${DATA_PATH}"

exit 0
