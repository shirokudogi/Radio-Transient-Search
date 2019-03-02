#!/bin/bash
#
# radiosearch.sh
#
# Created by:     Cregg C. Yancey
# Creation date:  Feb 18 2019
#
# Modified by:
# Modified date:
#
# PURPOSE: Implement the radio de-dispersion workflow.
#
# INPUT:
#
# OUTPUT:
#     


# Make sure extended regular expressions are supported.
shopt -s extglob

# User input test patterns.
AFFIRMATIVE='^(y|yes|yup|yea|yeah|ya)$'
INTEGER_NUM='^[+-]?[0-9]+$'
REAL_NUM='^[+-]?[0-9]+([.][0-9]+)?$'


USAGE='
radioextract

   radiosearch.sh [-n | --nprocs <num>] [-i | --install-dir <path>]
   [-w | --work-dir <path>] [-r | --results-dir <path>] [-s | --super-cluster] [-h | --help] 
   [-m | --memory-limit <MB>]

   Implements the phase of the radio transient search workflow that performs the de-dispersion 
   search to extract coherent signal power above threshold that may correspond to real astrophysical 
   events.


   OPTIONS:
      -n | --nprocs <num>:          Number of MPI processes to use.  This defaults to the number of
                                    processor cores on the machine.

      -s | --supercluster:         Specify to initialize for execution on a super-cluster.


      -i | --install-dir <path>:    Specify <path> as the path to the directory containing the
                                    radio transient search scripts.

      -w | --work-dir <path>:       Specify <path> as the path to the working directory for all
                                    intermediate and output files.

      -r | --results-dir <path>:    Specify <path> as the path to the results directory for all final
                                    results files.

      -l | --label <string>:        User-specified label (currently not used for anything).

      -m | --memory-limit <MB>:     Total memory usage limit, in MB, for generating spectrogram tiles.
                                    This is the size of a single spectrogram tile multiplied by the total
                                    number of processes.

      -c | --config-file <name>:    Name of the common configuration file.  This file is created in the
                                    working directory and then later moved to the results directory.

      -h | --help:                  Display this help message.
'



# ==== MAIN WORKFLOW FOR RADIOEXTRACT.SH ===
#
#
INSTALL_DIR=         # Install directory for radiotrans.
WORK_DIR=            # Working directory.
RESULTS_DIR=         # Results directory.
MEM_LIMIT=           # Total memory usage limit, in MB, for spectrogram tiles among all processes.
LABEL=               # User label attached to output files from data reduction.
NUM_PROCS=           # Number of concurrent processes to use under MPI
SUPERCLUSTER=0       # Flag denoting whether we should initialize for being on a supercluster.

COMMCONFIG_FILE=     # Name of the common configuration file.

MAX_PULSE=           # Maximum pulse width in seconds.
DM_START=            # Starting dispersion measure for search.
DM_END=              # Ending dispersion measure for search.
SNR_THRESHOLD=       # SNR detection threshold.


# Parse command-line arguments, but be sure to only accept the first value of an option or argument.
if [[ ${#} -gt 0 ]]; then
   while [ -n "${1}" -a -z "${DATA_PATH}" ]
   do
      case "${1}" in
         -h | --help) # Display the help message and then quit.
            echo "${USAGE}"
            exit 0
            ;;
         -i | --install-dir) # Specify the install directory path to the radio transient scripts.
            if [ -z "${INSTALL_DIR}" ]; then
               INSTALL_DIR="${2}"
            fi
            shift; shift
            ;;
         -n | --nprocs) # Specify the number of processes/processors to use
            if [ -z "${NUM_PROCS}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -lt 1 ]; then
                     NUM_PROC=1
                  else
                     NUM_PROCS=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         -s | --supercluster) # Specify that we need to initialize for execution on a supercluster.
            SUPERCLUSTER=1
            shift
            ;;
         -w | --work-dir) # Specify the working directory.
            if [ -z "${WORK_DIR}" ]; then
               WORK_DIR="${2}"
            fi
            shift; shift
            ;;
         -r | --results-dir) # Specify the results directory.
            if [ -z "${RESULTS_DIR}" ]; then
               RESULTS_DIR="${2}"
            fi
            shift; shift
            ;;
         -l | --label) # Specify a user label to attach to output files from the reduction.
            if [ -z "${LABEL}" ]; then
               LABEL="${2}"
            fi
            shift; shift
            ;;
         -m | --memory-limit) # Specify the total memory usage limit for the spectrogram tiles
                              # multiplied to the total number of processes.
            if [ -z "${MEM_LIMIT}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     MEM_LIMIT=${2}
                  else
                     MEM_LIMIT=16384
                  fi
               fi
            fi
            shift; shift
            ;;
         -c | --config-file) # Specify the name of the common configuration file.
            if [ -z "${COMMCONFIG_FILE}" ]; then
               # Just in case the user gives a full path, strip off the directory component.  We only
               # need a name, and the file is going to be created in ${WORK_DIR}.
               COMMCONFIG_FILE=$(basename "${2}")
            fi
            shift; shift
            ;;
         --snr-threshold) # Specify SNR detection threshold.
            if [ -z "${SNR_CUTOFF}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  SNR_THRESHOLD=${2}
               fi
            fi
            shift; shift
            ;;
         -s | --dm-start) # Specify the starting dispersion measure for search.
            if [ -z "${DM_START}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  DM_START=${2}
               fi
            fi
            shift; shift
            ;;
         -e | --dm-end) # Specify the ending dispersion measure for search.
            if [ -z "${DM_END}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  DM_END=${2}
               fi
            fi
            shift; shift
            ;;
         -p | --max-pulse-width) # Specify the maximum pulse width for search.
            if [ -z "${MAX_PULSE}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  MAX_PULSE=${2}
               fi
            fi
            shift; shift
            ;;
         -*) # Unknown option
            echo "WARNING: radiosearch.sh -> Unknown option"
            echo "     ${1}"
            echo "Ignored: may cause option and argument misalignment."
            shift 
            ;;
         *) # Get the data file path
            if [ -z "${DATA_PATH}" ]; then
               DATA_PATH="${1}"
            fi
            shift
            ;;
      esac
   done
else
   echo "ERROR: radiosearch.sh -> Nothing specified to do"
   echo "${USAGE}"
   exit 1
fi


# Check that specified install path exists and that all necessary components are contained.
if [ -z "${INSTALL_DIR}" ]; then
   INSTALL_DIR="OPT-INSTALL_DIR"
fi
if [ -d "${INSTALL_DIR}" ]; then
   package_modules=(dv.py apputils.py resume.sh utils.sh)
   for module in ${package_modules[*]}; do
      MODULE_PATH="${INSTALL_DIR}/${module}"
      if [ ! -f "${MODULE_PATH}" ]; then
         echo "ERROR: radiosearch.sh -> Missing package module"
         echo "     ${MODULE_PATH}"
         exit 1
      fi
   done
else
   echo "ERROR: radiosearch.sh -> Install path does not exist"
   echo "     ${INSTALL_DIR}"
   exit 1
fi

# Ensure that the working directory exists.
if [ -z "${WORK_DIR}" ]; then
   WORK_DIR="."
fi
if [ ! -d "${WORK_DIR}" ]; then
   echo "ERROR: radiosearch.sh -> working directory does not exist.  User may need to create it."
   echo "     ${WORK_DIR}"
   exit 1
fi

# Ensure that the results directory exists.
if [ -z "${RESULTS_DIR}" ]; then
   RESULTS_DIR="."
fi
if [ ! -d "${RESULTS_DIR}" ]; then
   echo "ERROR: radiosearch.sh -> results directory does not exist.  User may need to create it."
   echo "     ${RESULTS_DIR}"
   exit 1
fi

# Ensure that the common configuration filename is set.
if [ -z "${COMMCONFIG_FILE}" ]; then
   COMMCONFIG_FILE="radiotrans.ini"
fi

# Ensure that the memory limit is specified.
if [ -z "${MEM_LIMIT}" ]; then
   MEM_LIMIT=16384
fi

# Ensure that the SNR detection threshold is specified.
if [ -z "${SNR_THRESHOLD}" ]; then
   SNR_THRESHOLD=5.0
fi

# Ensure that the maximum pulse width is specified.
if [ -z "${MAX_PULSE}" ]; then
   MAX_PULSE=5.0
fi

# Ensure that the starting dispersion measure is specified.
if [ -z "${DM_START}" ]; then
   DM_START=30.0
fi

# Ensure that the ending dispersion measure is specified.
if [ -z "${DM_END}" ]; then
   DM_END=5.0
fi


# Source the utility functions.
source ${INSTALL_DIR}/utils.sh

# Source the resume functionality.
RESUME_CMD_FILEPATH="${RESULTS_DIR}/radiotrans_cmd.resume"
RESUME_VAR_FILEPATH="${RESULTS_DIR}/radiotrans_var.resume"
source ${INSTALL_DIR}/resume.sh

# If this is on a supercluster, then load the necessary modules for the supercluster to be able to 
# execute python scripts.
if [ ${SUPERCLUSTER} -eq 1 ]; then
   module reset
   module load mkl python openmpi
fi




# = RADIO TRANSIENT SEARCH DE-DISPERSION AND TRANSIENT EXTRACTION PHASE WORKFLOW =
#
#  User feedback to confirm run parameters.
echo "radiosearch.sh: Starting radio de-dispersed search workflow:"
echo
echo "   Radiotrans install dir = ${INSTALL_DIR}"
echo "   Working dir = ${WORK_DIR}"
echo "   Results dir = ${RESULTS_DIR}"
echo "   Num running processes = ${NUM_PROCS}"
echo "   Memory limit (MB) = ${MEM_LIMIT}"
echo "   Common parameters file = ${COMMCONFIG_FILE}"
echo
echo "   Run label = ${LABEL}"
echo "   SNR threshold = ${SNR_THRESHOLD}" 
echo "   Max. pulse width = ${MAX_PULSE}"
echo "   DM start = ${DM_START}"
echo "   DM end = ${DM_END}"
echo

# Confirm that the user wishes to proceed with the current configuration.
MENU_CHOICES=("yes" "no")
echo "radiosearch.sh: Proceed with the above parameters?"
PS3="Enter option number (1 or 2): "
select USER_ANS in ${MENU_CHOICES[*]}
do
   if [[ "${USER_ANS}" == "yes" ]]; then
      echo "radiosearch.sh: Proceding with de-dispersed search workflow..."
      break
   elif [[ "${USER_ANS}" == "no" ]]; then
      echo "radiosearch.sh: De-dispersed search workflow cancelled."
      exit 0
   else
      continue
   fi
done

# Workflow resume labels.  These are to label each executable stage of the workflow for use with
# resumecmd.
#
LBL_SEARCH0="De-disperse_Tune0"
LBL_SEARCH1="De-disperse_Tune1"
LBL_RESULTS="Results_Transfer"
LBL_CLEAN="Cleanup_Extract"
LBL_DELWORK="DeleteWorkingDir"

CMBPREFIX="spectrogram"
PULSEPREFIX="pulse"
if [ -n "${LABEL}" ]; then
   CMBPREFIX="${CMBPREFIX}_${LABEL}"
   PULSEPREFIX="${PULSEPREFIX}_${LABEL}"
fi

echo "     Performing de-dispersed search on tuning 0 data..."
resumecmd -l ${LBL_SEARCH0} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_DIR}/dv.py "${WORK_DIR}/rfibp-${CMBPREFIX}-T0.npy" \
   --memory-limit ${MEM_LIMIT} --work-dir "${WORK_DIR}" --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --dm-start ${DM_START} --dm-end ${DM_END} --max-pulse-width ${MAX_PULSE} \
   --snr-threshold ${SNR_THRESHOLD} --output-file "${WORK_DIR}/${PULSEPREFIX}-T0.txt"
report_resumecmd

echo "     Performing de-dispersed search on tuning 0 data..."
resumecmd -l ${LBL_SEARCH1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_DIR}/dv.py "${WORK_DIR}/rfibp-${CMBPREFIX}-T1.npy" \
   --memory-limit ${MEM_LIMIT} --work-dir "${WORK_DIR}" --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --dm-start ${DM_START} --dm-end ${DM_END} --max-pulse-width ${MAX_PULSE} --tuning1 \
   --snr-threshold ${SNR_THRESHOLD} --output-file "${WORK_DIR}/${PULSEPREFIX}-T1.txt"
report_resumecmd

# Determine exit status
if [ ${RESUME_LASTCMD_SUCCESS} -eq 1 ]; then
   echo "radiosearch.sh: De-dispersed search workflow completed successfully!"
   echo "radiosearch.sh: Workflow exiting with status 0."
   exit 0
else
   echo "radiosearch.sh: De-dispersed search workflow ended, but not all components were executed."
   echo "radiosearch.sh: Workflow exiting with status 1"
   exit 1
fi
