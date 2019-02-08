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
# NOTE: The ${INSTALL_DIR} template variable is replaced by my git-export.sh script with the path to which
#       the package is installed.  If you don't have my git-export.sh script, then you can just manually 
#       replace all instances of ${INSTALL_DIR} as necessary.


# Make sure extended regular expressions are supported.
shopt -s extglob

# User input test patterns.
AFFIRMATIVE='^(y|yes|yup|yea|yeah|ya)$'
INTEGER_NUM='^[+-]?[0-9]+$'
REAL_NUM='^[+-]?[0-9]+([.][0-9]+)?$'


USAGE='
radioreduce.sh

   radioreduce.sh [-t | --integrate-time <time>] [-n | --nprocs <num>] [-i | --install-dir <path>]
   [-w | --work-dir <path>] [-r | --results-dir <path>] [-s | --super-cluster] [-h | --help] 
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

      -c | --config-file <name>:    Name of the common configuration file.  This file is created in the
                                    working directory and then later moved to the results directory.

      -h | --help:                  Display this help message.
'



# ==== MAIN WORKFLOW FOR RADIOREDUCE.SH ===
#
#
# Set the install path for the radio transient search workflow scripts.  
# NOTE: the string 'OPT-INSTALL_DIR' is replaced by the git-export.sh script with the path to directory 
# in which the radio transient scripts have been installed.  However, the user is free to manually change
# this.
INSTALL_DIR=

DATA_PATH=           # Path to the radio time-series data file.
INTEGTIME=           # Spectral integration time in milliseconds.
WORK_DIR=            # Working directory.
RESULTS_DIR=         # Results directory.
MEM_LIMIT=           # Total memory usage limit, in MB, for spectrogram tiles among all processes.
LABEL=               # User label attached to output files from data reduction.
ENABLE_HANN=         # Commandline option string to enable Hann windowing in the data reduction.
DECIMATION=          # Decimation for producing coarse spectrogram.
RFI_STD=             # RFI standard deviation cutoff.
                     
NUM_PROCS=           # Number of concurrent processes to use under MPI
SUPERCLUSTER=        # Flag denoting whether we should initialize for being on a supercluster.

COMMCONFIG_FILE=     # Name of the common configuration file.

FLAG_SKIPMOVE=0      # Flag denoting whether to skip the final stage to transfer of results files to the
                     # results directory.



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
         -t | --integrate-time) # Specify the spectrogram integration time.
            if [ -z "${INTEGTIME}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  INTEGTIME=${2}
               fi
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
         --enable-hann) # Enable Hann windowing on the raw DFTs during reduction.
            ENABLE_HANN="--enable-hann"
            shift
            ;;
         --skip-transfer) # Skip transferring results files to the results directory.
            FLAG_SKIPMOVE=1
            shift
            ;;
         -d | --decimation) # Specify decimation for the coarse spectrogram.
            if [ -z "${DECIMATION}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     DECIMATION=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         --rfi-std-cutoff) # Specify RFI standard deviation cutoff.
            if [ -z "${RFI_STD}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  RFI_STD=${2}
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
            if [ -z "${DATA_PATH}" ]; then
               DATA_PATH="${1}"
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
if [ -z "${INTEGTIME}" ]; then
   INTEGTIME=1000
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
if [ -z "${INSTALL_DIR}" ]; then
   INSTALL_DIR="OPT-INSTALL_DIR"
fi
if [ -d "${INSTALL_DIR}" ]; then
   package_modules=(drx.py dp.py errors.py waterfall.py waterfallcombine.py apputils.py resume.sh 
                     utils.sh)
   for module in ${package_modules[*]}; do
      MODULE_PATH="${INSTALL_DIR}/${module}"
      if [ ! -f "${MODULE_PATH}" ]; then
         echo "ERROR: radioreduce.sh -> Missing package module"
         echo "     ${MODULE_PATH}"
         exit 1
      fi
   done
else
   echo "ERROR: radioreduce.sh -> Install path does not exist"
   echo "     ${INSTALL_DIR}"
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

# Ensure that the common configuration filename is set.
if [ -z "${COMMCONFIG_FILE}" ]; then
   COMMCONFIG_FILE="radiotrans.ini"
fi

# Check that the memory limits are specified.
if [ -z "${MEM_LIMIT}" ]; then
   MEM_LIMIT=16384
fi

# Check that the coarse spectrogram decimation is specified.
if [ -z "${DECIMATION}" ]; then
   DECIMATION=10000
fi

# Check that the RFI standard deviation cut-off is specified.
if [ -z "${RFI_STD}" ]; then
   RFI_STD=5.0
fi

# If a label was specified, create the label option.
if [ -n "${LABEL}" ]; then
   LABEL_OPT="--label ${LABEL}"
fi

# Source the utility functions.
source ${INSTALL_DIR}/utils.sh

# Source the resume functionality.
RESUME_CMD_FILEPATH="${WORK_DIR}/radiotrans_cmd.resume"
RESUME_VAR_FILEPATH="${WORK_DIR}/radiotrans_var.resume"
source ${INSTALL_DIR}/resume.sh

# If this is on a supercluster, then load the necessary modules for the supercluster to be able to 
# execute python scripts.
if [ -n "${SUPERCLUSTER}" ]; then
   module reset
   module load mkl python openmpi
fi



# = RADIO TRANSIENT SEARCH DATA REDUCTION PHASE WORKFLOW =
#
echo "radioreduce.sh: Starting radio data reduction workflow:"
# Workflow resume labels.  These are to label each executable stage of the workflow for use with
# resumecmd.
#
LBL_WATERFALL="Waterfall"
LBL_COMBINE0="WaterfallCombine_Tune0"
LBL_COMBINE1="WaterfallCombine_Tune1"
LBL_COARSEIMG0="WaterfallCoarseImg_Tune0"
LBL_COARSEIMG1="WaterfallCoarseImg_Tune1"
LBL_RESULTS="Results_Transfer"
LBL_CLEAN="Cleanup_Reduce"


# Generate the waterfall tiles for the reduced-data spectrogram
echo "radioreduce.sh: Generating waterfall tiles for spectrogram from ${DATA_PATH}..."
resumecmd -l ${LBL_WATERFALL} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_DIR}/waterfall.py \
   --integrate-time ${INTEGTIME} --work-dir "${WORK_DIR}" \
   ${ENABLE_HANN} ${LABEL_OPT} \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --memory-limit ${MEM_LIMIT} "${DATA_PATH}"
report_resumecmd


# Create the combined and coarse combined waterfalls for both tuning 0 and tuning 1.
echo "radioreduce.sh: Combining waterfall sample files into coarse spectrogram files..."
CMBPREFIX="spectrogram"
if [ -n "${LABEL}" ]; then
   CMBPREFIX="${CMBPREFIX}_${LABEL}"
fi
echo "radioreduce.sh: Combining tuning 0 waterfall files into coarse spectrogram..."
resumecmd -l ${LBL_COMBINE0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/waterfallcombine.py \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/${CMBPREFIX}-T0" \
   --decimation ${DECIMATION} \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" "${WORK_DIR}/waterfall*T0.npy"
report_resumecmd
echo "radioreduce.sh: Combining tuning 1 waterfall files into coarse spectrogram..."
resumecmd -l ${LBL_COMBINE1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/waterfallcombine.py \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/${CMBPREFIX}-T1" \
   --decimation ${DECIMATION} \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" "${WORK_DIR}/waterfall*T1.npy"
report_resumecmd

# Create images of the coarse combined waterfalls for tuning 0 and tuning 1.
echo "radioreduce.sh: Generating coarse spectrogram image for tuning 0..."
resumecmd -l ${LBL_COARSEIMG0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/watchwaterfall.py \
   --lower-FFT-index 0 --upper-FFT-index 4095 --label "Lower_Tuning" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --rfi-std-cutoff ${RFI_STD} \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/${CMBPREFIX}-T0.png" \
   "${WORK_DIR}/coarse-${CMBPREFIX}-T0.npy"
report_resumecmd
echo "radioreduce.sh: Generating coarse spectrogram image for tuning 1..."
resumecmd -l ${LBL_COARSEIMG1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/watchwaterfall.py \
   --lower-FFT-index 0 --upper-FFT-index 4095 --label "Higher_Tuning" --high-tuning \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --rfi-std-cutoff ${RFI_STD} \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/${CMBPREFIX}-T1.png" \
   "${WORK_DIR}/coarse-${CMBPREFIX}-T1.npy"
report_resumecmd


# Delete the waterfall files and other temporary files from the working directory.  We shouldn't need
# them after this point.
echo "radioreduce.sh: Cleaning up temporary and intermediate files (this may take a few minutes)..."
resumecmd -l ${LBL_CLEAN} -k ${RESUME_LASTCMD_SUCCESS} \
   delete_files "${WORK_DIR}/*.dtmp"
report_resumecmd


# Transfer results files to the results directory, if allowed by the user.
if [ ${FLAG_SKIPMOVE} -eq 0 ]; then
   # Move results files if the working directory and results directory are different.
   if [[ "${WORK_DIR}" != "${RESULTS_DIR}" ]]; then
      echo "radioreduce.sh: Transferring key results files to directory ${RESULTS_DIR}..."
      resumecmd -l ${LBL_RESULTS} -k ${RESUME_LASTCMD_SUCCESS} \
         transfer_files --src-dir "${WORK_DIR}" --dest-dir "${RESULTS_DIR}" \
         "${CMBPREFIX}*.npy" "coarse-${CMBPREFIX}*.npy" "waterfall*.npy" "*.png" \
         "${COMMCONFIG_FILE}"
      report_resumecmd
   else
      echo "radioreduce.sh: Skipping results transfer => working and results directories are the same."
   fi
else
      echo "radioreduce.sh: Skipping results transfer by user request."
fi

# Determine exit status
if [ ${RESUME_LASTCMD_SUCCESS} -eq 1 ]; then
   echo "radioreduce.sh: Radio data reduction workflow completed successfully!"
   echo "radioreduce.sh: Workflow exiting with status 0."
   exit 0
else
   echo "radioreduce.sh: Radio data reduction workflow ended, but not all components were executed."
   echo "radioreduce.sh: Workflow exiting with status -1"
   exit -1
fi
