#!/bin/bash

shopt -s extglob

# User input test patterns.
AFFIRMATIVE='^(y|yes|yup|yea|yeah|ya)$'
INTEGER_NUM='^[+-]?[0-9]+$'
REAL_NUM='^[+-]?[0-9]+([.][0-9]+)?$'


# Configure process parameters.
NUM_PROCS=$(nproc --all)   # Number of processes to use in the MPI environment.
MEM_LIMIT=32768            # Memory limit, in MBs, for creating waterfall tiles in memory.

# Configure radio run parameters.
DATA_DIR="/data/network/recent_data/jtsai"
DATA_FILENAME="057974_001488582"
DATA_PATH="${DATA_DIR}/${DATA_FILENAME}"
LABEL="GWRREDUCE"
INTEGTIME=24.03265   # Do not set this below 24.03265 to avoid corruption during RFI filtering and
                     # smoothing.
DECIMATION=4000
RFI_STD=5.0
SNR_CUTOFF=3.0
SG_PARAMS0=(151 2 151 2)
SG_PARAMS1=(111 2 151 2)
ENABLE_HANN=            # Set to "--enable-hann" to enable Hann window on raw data during reduction.
DATA_UTILIZE=1.0        # Fraction of raw data to use.  Positive values align to the beginning of the 
                        # raw data, while negative values align to the end.

# Configure file management parameters.
INSTALL_DIR="${HOME}/local/radiotrans"
WORK_DIR="/mnt/toaster/cyancey/${LABEL}"
RESULTS_DIR="${HOME}/analysis/${LABEL}"
SKIPMOVE_OPT=
DELWATERFALLS_OPT=
COMMCONFIG_FILE="config_${LABEL}.ini"

# Disable debug mode, by default. This has to be enabled by the user from the commandline.
DEFAULT_DEBUG=0


# Select whether we are using the release install of radiotrans or still using the developer version to
# debug issues.
if [[ ${#} -gt 0 ]]; then
   while [ -n "${1}" ]
   do
      case "${1}" in
         -D | --DEBUG) # Force enable default debugging configuration.
            echo "radiorun_lwa.sh: Force enabling default debugging configuration."
            DATA_DIR="/data/network/recent_data/jtsai"
            DATA_FILENAME="057974_001488582"
            DATA_PATH="${DATA_DIR}/${DATA_FILENAME}"
            LABEL="GWRDEBUG"
            INSTALL_DIR="${HOME}/dev/radiotrans"
            WORK_DIR="/mnt/toaster/cyancey/${LABEL}"
            RESULTS_DIR="${HOME}/analysis/${LABEL}"
            INTEGTIME=24.03265
            DECIMATION=4000
            RFI_STD=5.0
            SNR_CUTOFF=3.0
            SG_PARAMS0=(151 2 151 2)
            SG_PARAMS1=(111 2 151 2)
            ENABLE_HANN=

            COMMCONFIG_FILE="config_${LABEL}.ini"

            DEFAULT_DEBUG=1
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
                  echo "radiorun_lwa.sh: Cannot find install directory ${2}"
               fi
            fi
            shift; shift
            ;;
         -S | --small-node) # Lower the memory limit for the smaller nodes (ones having 32 GB total RAM)
                            # LWA.
            MEM_LIMIT=16384
            shift
            ;;
         -U | --data-utilization) # Specify RFI standard deviation cutoff.
            if [ -z "${DATA_UTILIZE}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  DATA_UTILIZE="${2}"
               fi
            fi
            shift; shift
            ;;
         --skip-transfer) # Skip transfer of results files to the results directory.
            SKIPMOVE_OPT="--skip-transfer"
            shift
            ;;
         --delete-waterfalls) # Delete waterfall file from the working directory at the end of the run.
            DELWATERFALLS_OPT="--delete-waterfalls"
            shift
            ;;
         *) # Ignore anything else.
            shift
            ;;
      esac
   done
fi

# Ensure the data file exists.
if [ -f "${DATA_PATH}" ]; then
   echo "radiorun_lwa.sh: ERROR => Data file ${DATA_PATH} not found."
   exit 1 
fi

# Create the working directory, if it doesn't exist.
if [ ! -d "${WORK_DIR}" ]; then
   mkdir -p "${WORK_DIR}"
   if [ ! -d "${WORK_DIR}" ]; then
      echo "Could not create working directory ${WORK_DIR}"
      exit 1
   fi
fi

# Create the results directory, if it doesn't exist.
if [ ! -d "${RESULTS_DIR}" ]; then
   mkdir -p "${RESULTS_DIR}"
   if [ ! -d "${RESULTS_DIR}" ]; then
      echo "Could not create results directory ${RESULTS_DIR}"
      exit 1
   fi
fi



# Build the command-line to perform data reduction.
CMD_REDUCE="${INSTALL_DIR}/radioreduce.sh"
CMD_REDUCE_OPTS=(--install-dir "${INSTALL_DIR}" --integrate-time ${INTEGTIME} \
      --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} ${ENABLE_HANN} \
      --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
      --decimation ${DECIMATION} --rfi-std-cutoff ${RFI_STD} --snr-cutoff ${SNR_CUTOFF} \
      --data-utilization ${DATA_UTILIZE} \
      --savitzky-golay0 "${SG_PARAMS0[*]}" --savitzky-golay1 "${SG_PARAMS1[*]}" \
      --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${SKIPMOVE_OPT} ${DELWATERFALLS_OPT})

# Perform the data reduction phase.
${CMD_REDUCE} ${CMD_REDUCE_OPTS[*]} "${DATA_PATH}"

exit 0
