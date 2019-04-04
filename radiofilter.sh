#!/bin/bash
#
# radiofilter.sh
#
# Created by:     Cregg C. Yancey
# Creation date:  August 30 2018
#
# Modified by:
# Modified date:
#
# PURPOSE: Implements RFI and bandpass filtration of the radio spectrogram.
#
# INPUT:
#
# OUTPUT:
#     


# Make sure extended regular expressions are supported.
shopt -s extglob


source "OPT-INSTALL_DIR/text_patterns.sh"
#source "${HOME}/dev/radiotrans/text_patterns.sh"   # Use only when debugging.


USAGE='
radiofilter.sh

   radiofilter.sh  [-n | --nprocs <num>] [-i | --install-dir <path>] [-w | --work-dir <path>] 
   [-r | --results-dir <path>] [-c | --super-cluster] [-h | --help] 
   [-0 | --coarse0-file <path>] [-1 | --coarse1-file <path>] <data_path> <waterfall files...>

   Implements the phase of the radio transient search workflow that performs RFI and bandpass filtration
   on the spectrograms for each of the tunings.  During this phase, images of the bandpass filtration
   are generated for user viewing. NOTE: assumes the spectrogram files are
   ${WORK_DIR}/spectrogram-T0.npy for tuning 0 and ${WORK_DIR}/spectrogram-T1.npy for tuning 1, if they 
   are not specified with options -0 and -1, respectively.


   ARGUMENTS:
      <data_path>: Path to the raw radio data file.
      <waterfall files...>: Paths to the waterfall files.

   OPTIONS:
      -n | --nprocs <num>:          Number of MPI processes to use.  This defaults to the number of
                                    processor cores on the machine.

      -s | --supercluster:         Specify to initialize for execution on a super-cluster.


      -i | --install-dir <path>:    Specify <path> as the path to the directory containing the
                                    radio transient search scripts.

      -0 | --coarse0-file <path>:  Path to the tuning 0 coarse combined waterfall file.

      -1 | --coarse1-file <path>:  Path to the tuning 1 coarse combined waterfall file.

      -w | --work-dir <path>:       Specify <path> as the path to the working directory for all
                                    intermediate and output files.

      -r | --results-dir <path>:    Specify <path> as the path to the results directory for all final
                                    results files.

      -l | --label <string>:        User-specified label (currently not used for anything).

      -h | --help:                  Display this help message.
'

INSTALL_DIR=
WORK_DIR=            # Working directory.
RESULTS_DIR=         # Results directory.
COMMCONFIG_FILE=     # Name of the common configuration file.

MEM_LIMIT=           # Total memory usage limit, in MB, for spectrogram tiles among all processes.
NUM_PROCS=           # Number of concurrent processes to use under MPI
SUPERCLUSTER=0       # Flag denoting whether we should initialize for being on a supercluster.

LABEL=               # User label attached to output files from data reduction.
LOWER_FFT0=          # Tuning 0 lower FFT index for bandpass filtering.
UPPER_FFT0=          # Tuning 0 upper FFT index for bandpass filtering.
LOWER_FFT1=          # Tuning 1 lower FFT index for bandpass filtering.
UPPER_FFT1=          # Tuning 1 upper FFT index for bandpass filtering.
BP_WINDOW=           # Bandpass smoothing window for the RFI filtering.
BL_WINDOW=           # Baseline smoothing window for the RFI filtering.

NO_INTERACT=0


# Parse command-line arguments, but be sure to only accept the first value of an option or argument.
if [[ ${#} -gt 0 ]]; then
   while [ -n "${1}" ]
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
         -l0 | --lower-fft-index0) # Specify lower FFT index for tuning 0.
            if [ -z "${LOWER_FFT0}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     LOWER_FFT0=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         -u0 | --upper-fft-index0) # Specify upper FFT index for tuning 0.
            if [ -z "${UPPER_FFT0}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     UPPER_FFT0=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         -l1 | --lower-fft-index1) # Specify lower FFT index for tuning 1.
            if [ -z "${LOWER_FFT1}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     LOWER_FFT1=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         -u1 | --upper-fft-index1) # Specify upper FFT index for tuning 1.
            if [ -z "${UPPER_FFT1}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     UPPER_FFT1=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         -bp | --bandpass-window) # Specify the bandpass smoothing window.
            if [ -z "${BP_WINDOW}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     BP_WINDOW=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         -bl | --baseline-window) # Specify the baseline smoothing window.
            if [ -z "${BL_WINDOW}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  if [ ${2} -gt 0 ]; then
                     BL_WINDOW=${2}
                  fi
               fi
            fi
            shift; shift
            ;;
         --no-interact) # Turn off user interaction.
            NO_INTERACT=1
            shift
            ;;
         *) # Ignore 
            shift 
            ;;
      esac
   done
else
   echo "ERROR: radiofilter.sh -> Nothing specified to do"
   echo "${USAGE}"
   exit 1
fi

# Check that specified install path exists and that all necessary components are contained.
if [ -z "${INSTALL_DIR}" ]; then
   INSTALL_DIR="OPT-INSTALL_DIR"
fi
if [ -d "${INSTALL_DIR}" ]; then
   package_modules=(rfibandpass.py apputils.py resume.sh utils.sh)
   for module in ${package_modules[*]}; do
      MODULE_PATH="${INSTALL_DIR}/${module}"
      if [ ! -f "${MODULE_PATH}" ]; then
         echo "ERROR: radiofilter.sh -> Missing package module"
         echo "     ${MODULE_PATH}"
         exit 1
      fi
   done
else
   echo "ERROR: radiofilter.sh -> Install path does not exist"
   echo "     ${INSTALL_DIR}"
   exit 1
fi

# Check that the working directory exists.
if [ -z "${WORK_DIR}" ]; then
   WORK_DIR="."
fi
if [ ! -d "${WORK_DIR}" ]; then
   echo "ERROR: radiofilter.sh -> working directory does not exist.  User may need to create it."
   echo "     ${WORK_DIR}"
   exit 1
fi

# Check that the results directory exists.
if [ -z "${RESULTS_DIR}" ]; then
   RESULTS_DIR="."
fi
if [ ! -d "${RESULTS_DIR}" ]; then
   echo "ERROR: radiofilter.sh -> results directory does not exist.  User may need to create it."
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



# = RADIO TRANSIENT SEARCH RFI AND BANDPASS FILTRATION PHASE WORKFLOW =
#
LBL_TUNE0FCL="TUNE0FCL"
LBL_TUNE0FCH="TUNE0FCH"
LBL_TUNE1FCL="TUNE1FCL"
LBL_TUNE1FCH="TUNE1FCH"
LBL_BPWINDOW="BPWINDOW"
LBL_BLWINDOW="BLWINDOW"
resumevar -l ${LBL_TUNE0FCL} LOWER_FFT0 0       # Lower FFT index for tuning 0.
resumevar -l ${LBL_TUNE0FCH} UPPER_FFT0 4095    # Upper FFT index for tuning 0.
resumevar -l ${LBL_TUNE1FCL} LOWER_FFT1 0       # Lower FFT index for tuning 1.
resumevar -l ${LBL_TUNE1FCH} UPPER_FFT1 4095    # Upper FFT index for tuning 1.
resumevar -l ${LBL_BPWINDOW} BP_WINDOW 11       # Bandpass smoothing window.
resumevar -l ${LBL_BLWINDOW} BL_WINDOW 51       # Baseline smoothing window.

#  User feedback to confirm run parameters.
echo "radiofilter.sh: Starting radio data reduction workflow:"
echo
echo "   Radiotrans install dir = ${INSTALL_DIR}"
echo "   Working dir = ${WORK_DIR}"
echo "   Results dir = ${RESULTS_DIR}"
echo "   Num running processes = ${NUM_PROCS}"
echo "   Memory limit (MB) = ${MEM_LIMIT}"
echo "   Common parameters file = ${COMMCONFIG_FILE}"
echo
echo "   Run label = ${LABEL}"
echo "   Tuning 0 lower FFT Index = ${LOWER_FFT0}"
echo "   Tuning 0 upper FFT Index = ${UPPER_FFT0}"
echo "   Tuning 1 lower FFT Index = ${LOWER_FFT1}"
echo "   Tuning 1 upper FFT Index = ${UPPER_FFT1}"
echo "   Bandpass smoothing window = ${BP_WINDOW}"
echo "   Baseline smoothing window = ${BL_WINDOW}"
echo

if [ ${NO_INTERACT} -eq 0 ]; then
   # Confirm that the user wishes to proceed with the current configuration.
   MENU_CHOICES=("yes" "no")
   echo "radiofilter.sh: Proceed with the above parameters?"
   PS3="Enter option number (1 or 2): "
   select USER_ANS in ${MENU_CHOICES[*]}
   do
      if [[ "${USER_ANS}" == "yes" ]]; then
         echo "radiofilter.sh: Proceding with reduction workflow..."
         break
      elif [[ "${USER_ANS}" == "no" ]]; then
         echo "radiofilter.sh: Reduction workflow cancelled."
         exit 1
      else
         continue
      fi
   done
fi

# Workflow resume labels.  These are to label each executable stage of the workflow for use with
# resumecmd.
#

LBL_RFIBANDPASS0="RFIBandpass_Tune0"
LBL_RFIBANDPASS1="RFIBandpass_Tune1"
LBL_COARSERFIBP0="CoarseRFIBandpass_Tune0"
LBL_COARSERFIBP1="CoarseRFIBandpass_Tune1"
LBL_COARSEIMG0="RFIBandpass_Tune0IMG"
LBL_COARSEIMG1="RFIBandpass_Tune1IMG"
LBL_CLEAN="Cleanup_filter"


CMBPREFIX="spectrogram"
if [ -n "${LABEL}" ]; then
   CMBPREFIX="${CMBPREFIX}_${LABEL}"
fi
# Perform data smoothing, RFI cleaning, and bandpass filtering of detailed spectrogram.
echo "    Performing RFI-bandpass filtering of tuning 0 spectrogram..."
resumecmd -l ${LBL_RFIBANDPASS0} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_DIR}/rfibandpass.py "${WORK_DIR}/${CMBPREFIX}-T0.npy" \
   --lower-fft-index ${LOWER_FFT0} --upper-fft-index ${UPPER_FFT0} \
   --bandpass-window ${BP_WINDOW} --baseline-window ${BL_WINDOW} \
   --output-file "${WORK_DIR}/rfibp-${CMBPREFIX}-T0.npy" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --work-dir ${WORK_DIR} 
report_resumecmd
echo "    Performing RFI-bandpass filtering of tuning 1 spectrogram..."
resumecmd -l ${LBL_RFIBANDPASS1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_DIR}/rfibandpass.py "${WORK_DIR}/${CMBPREFIX}-T1.npy" \
   --lower-fft-index ${LOWER_FFT1} --upper-fft-index ${UPPER_FFT1} --tuning1 \
   --bandpass-window ${BP_WINDOW} --baseline-window ${BL_WINDOW} \
   --output-file "${WORK_DIR}/rfibp-${CMBPREFIX}-T1.npy" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --work-dir ${WORK_DIR} 
report_resumecmd


# Create coarse versions of the RFI-bandpass filtered spectrograms.
echo "radioreduce.sh: Creating coarse RFI-bandpass filtered spectrogram for tuning 0..."
resumecmd -l ${LBL_COARSERFIBP0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/coarse_rfibp.py \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/rfibpcoarse-${CMBPREFIX}-T0" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" "${WORK_DIR}/rfibp-${CMBPREFIX}-T0.npy"
report_resumecmd
echo "radioreduce.sh: Creating coarse RFI-bandpass filtered spectrogram for tuning 1..."
resumecmd -l ${LBL_COARSERFIBP0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/coarse_rfibp.py \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/rfibpcoarse-${CMBPREFIX}-T1" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" "${WORK_DIR}/rfibp-${CMBPREFIX}-T1.npy"
report_resumecmd


# Create images of the coarse RFI-bandpass filtered spectrograms for tuning 0 and tuning 1.
echo "radiofilter: Generating coarse RFI-bandpass spectrogram image for tuning 0..."
resumecmd -l ${LBL_COARSEIMG0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/watchwaterfall.py \
   --lower-FFT-index 0 --upper-FFT-index 4095 --label "${LABEL}_Low" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --rfi-std-cutoff 5.0 \
   --savitzky-golay "151,2,151,2" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/rfibpcoarse-${CMBPREFIX}-T0.png" \
   --snr-cutoff ${SNR_CUTOFF} "${WORK_DIR}/rfibpcoarse-${CMBPREFIX}-T0.npy"
report_resumecmd
echo "radiofilter: Generating coarse RFI-bandpass spectrogram image for tuning 1..."
resumecmd -l ${LBL_COARSEIMG1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/watchwaterfall.py \
   --lower-FFT-index 0 --upper-FFT-index 4095 --label "${LABEL}_High" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --rfi-std-cutoff 5.0 \
   --savitzky-golay "111,2,151,2" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/rfibpcoarse-${CMBPREFIX}-T1.png" \
   --snr-cutoff ${SNR_CUTOFF} "${WORK_DIR}/rfibpcoarse-${CMBPREFIX}-T1.npy"
report_resumecmd

# Clean up temporary files.
resumecmd -l ${LBL_CLEAN} -k ${RESUME_LASTCMD_SUCCESS} \
   delete_files "${WORK_DIR}/*.dtmp"
report_resumecmd

# Determine exit status
if [ -z "${RESUME_LASTCMD_SUCCESS}" ] || [ ${RESUME_LASTCMD_SUCCESS} -eq 1 ]; then
   echo "radiofilter.sh: RFI-bandpass filtration workflow completed successfully!"
   echo "radiofilter.sh: Workflow exiting with status 0."
   echo
   exit 0
else
   echo "radiofilter.sh: RFI-bandpass filtration workflow ended, but not all components were executed."
   echo "radiofilter.sh: Workflow exiting with status 1"
   echo
   exit 1
fi
