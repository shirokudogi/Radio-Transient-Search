#!/bin/bash

# Configure run parameters.
DATA_DIR="/data/network/recent_data/jtsai"   # Directory path containing radio data file.
DATA_FILENAME="057974_001488582"             # Radio data filename.
DATA_PATH="${DATA_DIR}/${DATA_FILENAME}"     # Full path to the radio data file.

INTEGTIME=9.405            # Spectral integration time in milliseconds.
NUM_PROCS=$(nproc --all)   # Number of processes to use in the MPI environment.
MEM_LIMIT=32768            # Memory limit, in MBs, for creating waterfall tiles in memory.

INSTALL_DIR="${HOME}/local/radiotrans"
WORK_DIR="/mnt/toaster/cyancey"
RESULTS_DIR="${HOME}/analysis/gwradio2017"
DEFAULT_DEBUG=0
COMMCONFIG_FILE=


# Select whether we are using the release install of radiotrans or still using the developer version to
# debug issues.
if [[ ${#} -gt 0 ]]; then
   while [ -n "${1}" ]
   do
      case "${1}" in
         -D | --DEBUG) # Force enable default debugging configuration.
            echo "Force enabling default debugging configuration."
            INSTALL_DIR="${HOME}/dev/radiotrans"
            RESULTS_DIR="${HOME}/analysis/debug"
            DEFAULT_DEBUG=1
            shift
            ;;
         -I | --install-dir) # Set the install directory to the specified location.
            if [ ${DEFAULT_DEBUG} -eq 0]; then
               if [ -d "${2}" ]; then
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
               if [ -d "${2}" ]; then
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
            if [ -d "${2}" ]; then
               WORK_DIR="${2}"
            else
               echo "Cannot find install directory ${2}"
            fi
            shift; shift
            ;;
         -F | --data-file) # Set the radio data file to the specified path.
            if [ -f "${2}" ]; then
               DATA_PATH="${2}"
            else
               echo "Cannont find radio data file ${2}"
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
         *) # Ignore anything else.
            shift
            ;;
      esac
   done
fi

# Create the working directory, if it doesn't exist.
if [ ! -d "${WORK_DIR}" ]; then
   mkdir "${WORK_DIR}"
   if [ ! -d "${WORK_DIR}" ]; then
      echo "Could not create working directory ${WORK_DIR}"
      exit 1
   fi
fi

# Set the common configuration file path
if [ -z "${COMMCONFIG_FILE}" ]; then
   COMMCONFIG_FILE="radiotrans.ini"
fi

# Build the command-line to run radiotrans.sh
CMD="${INSTALL_DIR}/radioreduce.sh"
CMD_OPTS=( --install-dir "${INSTALL_DIR}" --integrate-time ${INTEGTIME} \
      --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} \
      --work-dir "${WORK_DIR}" --config-file "${WORK_DIR}/${COMMCONFIG_FILE}" \
      --results-dir "${RESULTS_DIR}")

# Run the radiotrans.sh script.
${CMD} ${CMD_OPTS[*]} "${DATA_PATH}"

exit 0
