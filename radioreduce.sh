#!/bin/bash
#
# radioreduce.sh
#
# Created by:     Cregg C. Yancey
# Creation date:  August 30 2018
#
# Modified by:
# Modified date:
#
# PURPOSE: Implement data reduction and coarse spectrogram production phase of the radio transient
#           search workflow.
#
# INPUT:
#
# OUTPUT:
#     
# NOTE: The ${INSTALL_PATH} template variable is replaced by my git-export.sh script with the path to which
#       the package is installed.  If you don't have my git-export.sh script, then you can just manually 
#       replace all instances of ${INSTALL_PATH} as necessary.


# Make sure extended regular expressions are supported.
shopt -s extglob

# Comparison strings for affirmative input from user.
AFFIRMATIVE='^(y|yes|yup|yea|yeah|ya)$'

# Set the install path for the radio transient search workflow scripts.  
# NOTE: the string 'OPT-INSTALL_DIR' is replaced by the git-export.sh script with the path to directory 
# in which the radio transient scripts have been installed.  However, the user is free to manually change
# this.
INSTALL_PATH="OPT-INSTALL_DIR"


USAGE='
radioreduce.sh

   radioreduce.sh [-t | --integrate-time <time>] [-n | --nprocs <num>] [-i | --install-dir <path>]
   [-w | --work-dir <path>] [-r | --results-dir <path>] [-c | --super-cluster] [-h | --help] 
   [-m | --memory-limit <MB>] <data-file-path>

   Implements the phase of the radio transient search workflow that reduces the raw data to a
   time-integrated power spectrogram. In addition, a coarse version of the spectrogram is created for
   visual inspection by the user, particularly for use during the bandpass and background filtration
   phase.


   ARGUMENTS:
      <data-file-path>: path to the radio data file.

   OPTIONS:
      -t | --integrate-time <time>: Specify <time> as the integration time, in milliseconds, for each
                                    time-slice in power spectrogram.

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

      -h | --help:                  Display this help message.
'



# ==== MAIN WORKFLOW FOR RADIOREDUCE.SH ===
#
#

DATA_PATH=           # Path to the radio time-series data file.
SPECTINTEGTIME=      # Spectral integration time in seconds.
WORK_DIR=            # Working directory.
RESULTS_DIR=         # Results directory.
MEM_LIMIT=           # Total memory usage limit, in MB, for spectrogram tiles among all processes.
LABEL=               # User label attached to output files from data reduction.
                     
NUM_PROCS=           # Number of concurrent processes to use under MPI
SUPERCLUSTER=        # Flag denoting whether we should initialize for being on a supercluster.


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
            if [ -z "${INSTALL_PATH}" ]; then
               INSTALL_PATH="${2}"
            fi
            shift; shift
            ;;
         -t | --integrate-time) # Specify the spectrogram integration time.
            if [ -z "${SPECTINTEGTIME}" ]; then
               if [[ "${2}" =~ "${REAL_NUM}" ]]; then
                  SPECTINTEGTIME=${2}
               fi
            fi
            shift; shift
            ;;
         -n | --nprocs) # Specify the number of processes/processors to use
            if [ -z "${NUM_PROCS}" ]; then
               if [[ "${2}" =~ "${INTEGER_NUM}" ]]; then
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
            SUPERCLUSTER="True"
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
               if [[ "${2}" =~ "${INTEGER_NUM}" ]]; then
                  if [ ${2} -gt 0 ]; then
                     MEM_LIMIT=${2}
                  else
                     MEM_LIMIT=16
                  fi
               fi
            fi
            shift; shift
            ;;
         -*) # Unknown option
            echo "WARNING: radioreduce.sh -> Unknown option"
            echo "     ${1}"
            echo "Ignored: may cause option and argument misalignment."
            shift 
            ;;
         *) # Get the data file path
            if [ -z "${DATA_PATH}" ]
               DATA_PATH="${2}"
            fi
            shift
            ;;
      esac
   done
else
   echo "ERROR: radioreduce.sh -> Nothing specified to do"
   echo "${USAGE}"
   exit 1
fi

# Check that the spectral integration time was specified.
if [ -z "${SPECTINTEGTIME}" ]; then
   SPECTINTEGTIME=1000
fi

# Check that a valid data file path has been specified and that the file exists.
if [ -n "${DATA_PATH}" ]; then
   if [ ! -f "${DATA_PATH}" ]; then
      echo "ERROR: radioreduce.sh -> Data file path not found"
      echo "     ${DATA_PATH}"
      exit 1
   fi
else
   echo "ERROR: radioreduce.sh -> Must provide a path to the data file."
   exit 1
fi

# Check that specified install path exists and that all necessary components are contained.
if [ -z "${INSTALL_PATH}" ]; then
   INSTALL_PATH="."
fi
if [ -d "${INSTALL_PATH}" ]; then
   package_modules=(drx.py dp.py errors.py waterfall.py waterfallcombine.py apputils.py resume.sh 
                     utils.sh)
   for module in ${package_modules[*]}; do
      MODULE_PATH="${INSTALL_PATH}/${module}"
      if [ ! -f "${MODULE_PATH}" ]; then
         echo "ERROR: radioreduce.sh -> Missing package module"
         echo "     ${MODULE_PATH}"
         exit 1
      fi
   done
else
   echo "ERROR: radioreduce.sh -> Install path does not exist"
   echo "     ${INSTALL_PATH}"
   exit 1
fi

# Check that the working directory exists.
if [ -z "${WORK_DIR}" ]; then
   WORK_DIR="."
fi
if [ ! -d "${WORK_DIR}" ]; then
   echo "ERROR: radioreduce.sh -> working directory does not exist.  User may need to create it."
   echo "     ${WORK_DIR}"
   exit 1
fi

# Check that the results directory exists.
if [ -z "${RESULTS_DIR}" ]; then
   RESULTS_DIR="."
fi
if [ ! -d "${RESULTS_DIR}" ]; then
   echo "ERROR: radioreduce.sh -> results directory does not exist.  User may need to create it."
   echo "     ${RESULTS_DIR}"
   exit 1
fi

# Check that the memory limits are specified.
if [ -z "${MEM_LIMIT}" ]; then
   MEM_LIMIT=16
fi

# Source the utility functions.
source ${INSTALL_PATH}/utils.sh

# Source the resume functionality.
RESUME_CMD_FILEPATH="${WORK_DIR}/radiotrans_cmd.resume"
RESUME_VAR_FILEPATH="${WORK_DIR}/radiotrans_var.resume"
source ${INSTALL_PATH}/resume.sh

# If this is on a supercluster, then load the necessary modules for the supercluster to be able to 
# execute python scripts.
if [ -n "${SUPERCLUSTER}" ]; then
   module reset
   module load mkl python openmpi
fi



# = RADIO TRANSIENT SEARCH DATA REDUCTION PHASE WORKFLOW =
#
echo "Starting radiotrans workflow:"
# Workflow resume labels.  These are to label each executable stage of the workflow for use with
# resumecmd.
#
LBL_WATERFALL="Waterfall"
LBL_COMBINE0="WaterfallCombine_Tune0"
LBL_COMBINE1="WaterfallCombine_Tune1"
LBL_RESULTS="Results_Reduce"
LBL_CLEAN="Cleanup_Reduce"


# Generate the coarse spectrogram
COMMCONFIGFILE="${WORK_DIR}/radiotrans.ini"
echo "    Generating waterfall samples for spectrogram from ${DATA_PATH}..."
resumecmd -l ${LBL_WATERFALL} mpirun -np ${NUM_PROCS} python ${INSTALL_PATH}/waterfall.py \
   --integrate-time ${SPECTINTEGTIME} --work-dir ${WORK_DIR} \
   --commconfig "${COMMCONFIGFILE}" --memory-limit ${MEM_LIMIT} "${DATA_PATH}"
report_resumecmd


# Combine the individual waterfall sample files into singular coarse and detailed spectrogram files.
echo "    Combining waterfall sample files into coarse and detailed spectrogram files..."
# DATAFILENAME=$(basename ${DATA_PATH})
# DATANAME="${DATAFILENAME%.*}"
COARSEFILE="coarsewaterfall"
SPECTFILE="combinedwaterfall"
resumecmd -l ${LBL_COMBINE0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_PATH}/waterfallcombine.py \
   --work-dir "${WORK_DIR}" \
   --outfile "${WORK_DIR}/${COARSEFILE}-T0" \
   --commconfig "${COMMCONFIGFILE}" "${WORK_DIR}/waterfall*T0.npy"
report_resumecmd

resumecmd -l ${LBL_COMBINE1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_PATH}/waterfallcombine.py \
   --work-dir "${WORK_DIR}" \
   --outfile "${WORK_DIR}/${COARSEFILE}-T1" \
   --commconfig "${COMMCONFIGFILE}" "${WORK_DIR}/waterfall*T1.npy"
report_resumecmd


# Delete the waterfall files and other temporary files from the working directory.  We shouldn't need
# them after this point.
echo "Cleaning up waterfall and other temporary files (this may take a few minutes)..."
resumecmd -l ${LBL_CLEAN} -k ${RESUME_LASTCMD_SUCCESS} \
   delete_files "${WORK_DIR}/*.dtmp"
report_resumecmd


# Move the remaining results files to the specified results directory, if it is different from the
# working directory.
if [[ "${WORK_DIR}" != "${RESULTS_DIR}" ]]; then
   resumecmd -l ${LBL_RESULTS} -k ${RESUME_LASTCMD_SUCCESS} \
      transfer_files --src-dir "${WORK_DIR}" --dest-dir "${RESULTS_DIR}" \
      "${COARSEFILE}.npy" "${SPECTFILE}-T0.npy" "${SPECTFILE}-T1.npy"
   report_resumecmd
fi

