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

# User input test patterns.
AFFIRMATIVE='^(y|yes|yup|yea|yeah|ya)$'
INTEGER_NUM='^[+-]?[0-9]+$'
REAL_NUM='^[+-]?[0-9]+([.][0-9]+)?$'



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

DATA_PATH=           # Path to the radio time-series data file.
INTEGTIME=           # Spectral integration time in milliseconds.
WORK_DIR=            # Working directory.
RESULTS_DIR=         # Results directory.
MEM_LIMIT=           # Total memory usage limit, in MB, for spectrogram tiles among all processes.
LABEL=               # User label attached to output files from data reduction.
ENABLE_HANN=         # Commandline option string to enable Hann windowing in the data reduction.
DECIMATION=          # Decimation for producing coarse spectrogram.
RFI_STD=             # RFI standard deviation cutoff.
DATA_UTILIZE=        # Fraction of the spectrogram lines to output from the raw data.
                     
NUM_PROCS=           # Number of concurrent processes to use under MPI
SUPERCLUSTER=        # Flag denoting whether we should initialize for being on a supercluster.

COMMCONFIG_FILE=     # Name of the common configuration file.

FLAG_SKIPMOVE=0      # Flag denoting whether to skip the final stage to transfer of results files to the
                     # results directory.

FLAG_DELWATERFALLS=0   # Flag denoting whether to delete waterfall files at the end of the run to
                           # help save space.



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
         --delete-waterfalls) # Specify deletion of waterfall files at the end of the run.
            FLAG_DELWATERFALLS=1
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
         -u | --data-utilization) # Specify RFI standard deviation cutoff.
            if [ -z "${DATA_UTILIZE}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  DATA_UTILIZE=${2}
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
         --snr-cutoff) # Specify SNR ceiling cutoff.
            if [ -z "${SNR_CUTOFF}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  SNR_CUTOFF=${2}
               fi
            fi
            shift; shift
            ;;
         -sg0 | --savitzky-golay0) # Specify Savitzky-Golay smoothing parameters for tuning 0.
            if [ -z "${SG_PARAMS0}" ]; then
               ARGS=(${2} ${3} ${4} ${5})
               for param in ${AGRS[*]}
               do
                  if [[ "${param}" =~ ${INTEGER_NUM} ]]; then
                     SG_PARAMS0=("${SG_PARAMS0[*]}" "${param}")
                  else
                     echo "radiorun_lwa.sh: ERROR => Savitzky-Golay0 values must be integers."
                     exit -1
                  fi
               done
            fi
            shift; shift; shift; shift; shift
            ;;
         -sg1 | --savitzky-golay1) # Specify Savitzky-Golay smoothing parameters for tuning 0.
            if [ -z "${SG_PARAMS1}" ]; then
               ARGS=(${2} ${3} ${4} ${5})
               for param in ${AGRS[*]}
               do
                  if [[ "${param}" =~ ${INTEGER_NUM} ]]; then
                     SG_PARAMS1=("${SG_PARAMS1[*]}" "${param}")
                  else
                     echo "radiorun_lwa.sh: ERROR => Savitzky-Golay0 values must be integers."
                     exit -1
                  fi
               done
            fi
            shift; shift; shift; shift; shift
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

# Check that the data utilization fraction is specified.
if [ -z "${DATA_UTILIZE}" ]; then
   DATA_UTILIZE=1.0
fi

# Check that the RFI standard deviation cut-off is specified.
if [ -z "${RFI_STD}" ]; then
   RFI_STD=5.0
fi

# Check that the SNR ceiling cutoff is specified.
if [ -z "${SNR_CUTOFF}" ]; then
   SNR_CUTOFF=3.0
fi

# Check Savitzky-Golay smoothing parameters are specified.
if [ -z "${SG_PARAMS0}" ]; then
   SG_PARAMS0=(151 2 151 2)
fi
if [ -z "${SG_PARAMS1}" ]; then
   SG_PARAMS1=(111 2 151 2)
fi

# If a label was specified, create the label option.
if [ -n "${LABEL}" ]; then
   LABEL_OPT="--label ${LABEL}"
fi

# Source the utility functions.
source ${INSTALL_DIR}/utils.sh

# Source the resume functionality.
RESUME_CMD_FILEPATH="${RESULTS_DIR}/radiotrans_cmd.resume"
RESUME_VAR_FILEPATH="${RESULTS_DIR}/radiotrans_var.resume"
source ${INSTALL_DIR}/resume.sh

# If this is on a supercluster, then load the necessary modules for the supercluster to be able to 
# execute python scripts.
if [ -n "${SUPERCLUSTER}" ]; then
   module reset
   module load mkl python openmpi
fi



# = RADIO TRANSIENT SEARCH RFI AND BANDPASS FILTRATION PHASE WORKFLOW =
#
#  User feedback to confirm run parameters.
echo "radioreduce.sh: Starting radio data reduction workflow:"
echo
echo "   Radiotrans install dir = ${INSTALL_DIR}"
echo "   Working dir = ${WORK_DIR}"
echo "   Results dir = ${RESULTS_DIR}"
echo "   Num running processes = ${NUM_PROCS}"
echo "   Memory limit (MB) = ${MEM_LIMIT}"
echo "   Common parameters file = ${COMMCONFIG_FILE}"
echo
echo "   Run label = ${LABEL}"
echo "   Integration time = ${INTEGTIME}"
echo "   Raw data utilization = ${DATA_UTILIZE}"
if [ -z "${ENABLE_HANN}" ]; then
   echo "   Enable Hann windowing = false"
else
   echo "   Enable Hann windowing = true"
fi
echo "   Coarse spectrogram decimation = ${DECIMATION}"
echo "   RFI standard deviation cutoff = ${RFI_STD}"
echo "   SNR cutoff = ${SNR_CUTOFF}" 
echo "   Savitzky-Golay parameters, tuning 0 = ${SG_PARAMS0[*]}"
echo "   Savitzky-Golay parameters, tuning 1 = ${SG_PARAMS1[*]}"
if [ ${FLAG_SKIPMOVE} -eq 0 ]; then
   echo "   Transfer to results dir = false"
else
   echo "   Transfer to results dir = true"
fi
if [ ${FLAG_DELWATERFALLS} -eq 0 ]; then
   echo "   Delete reduced waterfall files = false"
else
   echo "   Delete reduced waterfall files = true"
fi
echo

# Confirm that the user wishes to proceed with the current configuration.
MENU_CHOICES=("yes" "no")
echo "radioreduce.sh: Proceed with the above parameters?"
PS3="Enter option number (1 or 2): "
select USER_ANS in ${MENU_CHOICES[*]}
do
   if [[ "${USER_ANS}" == "yes" ]]; then
      echo "radioreduce.sh: Proceding with reduction workflow..."
      break
   elif [[ "${USER_ANS}" == "no" ]]; then
      echo "radioreduce.sh: Reduction workflow cancelled."
      exit 0
   else
      continue
   fi
done

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
LBL_DELWATERFALL="Delete_Waterfalls"
LBL_BANDPASSIMG0="WaterfallBandpassImg_Tune0"
LBL_BANDPASSIMG1="WaterfallBandpassImg_Tune1"
LBL_BASELINEIMG0="WaterfallBaselineImg_Tune0"
LBL_BASELINEIMG1="WaterfallBaselineImg_Tune1"
LBL_SGBANDPASSIMG0="WaterfallSGBandpassImg_Tune0"
LBL_SGBANDPASSIMG1="WaterfallSGBandpassImg_Tune1"
LBL_SGBASELINEIMG0="WaterfallSGBaselineImg_Tune0"
LBL_SGBASELINEIMG1="WaterfallSGBaselineImg_Tune1"
LBL_DELWORK="DeleteWorkingDir"


# View the spectrograms for the low and high frequency tunings and adjust the bandpass filtration for
# each tuning according to the user's specification.
#
LBL_TUNE0FCL="TUNE0FCL"
LBL_TUNE0FCH="TUNE0FCH"
LBL_TUNE1FCL="TUNE1FCL"
LBL_TUNE1FCH="TUNE1FCH"

LBL_BANDPASS0="BandpassCheck_Tune0"
LBL_BANDPASS1="BandpassCheck_Tune1"
LBL_SPECTROGRAM0="SpectrogramCheck_Tune0"
LBL_SPECTROGRAM1="SpectrogramCheck_Tune1"
LBL_RFIBANDPASS0="RFIBandpass_Tune0"
LBL_RFIBANDPASS1="RFIBandpass_Tune1"
LBL_RESULTS="Results_filter"
LBL_CLEAN="Cleanup_filter"

resumevar -l ${LBL_TUNE0FCL} TUNE0_FCL 0         # Lower FFT index for the low tuning frequency.
resumevar -l ${LBL_TUNE0FCH} TUNE0_FCH 4094      # Upper FFT index for the low tuning frequency.
resumevar -l ${LBL_TUNE1FCL} TUNE1_FCL 0       # Lower FFT index for the high tuning frequency.
resumevar -l ${LBL_TUNE1FCH} TUNE1_FCH 4094    # Upper FFT index for the high tuning frequency.


# Perform data smoothing, RFI cleaning, and bandpass filtering of detailed spectrogram.
WATERFALL0_PATHS=("${WATERFALL_DIR}/waterfall*T0.npy") 
WATERFALL1_PATHS=("${WATERFALL_DIR}/waterfall*T1.npy") 
echo "    Performing data smoothing, RFI cleaning, and bandpass filtering of detailed spectrogram..."
resumecmd -l ${LBL_RFIBANDPASS0} ${RESUME_FORCE_OPT} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_PATH}/rfibandpass.py \
   --lower-cutoff ${TUNE0_FCL} --upper-cutoff ${TUNE0_FCH} \
   --bandpass-window 10 --baseline-window 50 --work-dir ${WORK_DIR} \
   --prefix "rfibp" ${WATERFALL0_PATHS[*]}
report_resumecmd
resumecmd -l ${LBL_RFIBANDPASS1} ${RESUME_FORCE_OPT} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_PATH}/rfibandpass.py \
   --lower-cutoff ${TUNE1_FCL} --upper-cutoff ${TUNE1_FCH} \
   --bandpass-window 10 --baseline-window 50 --work-dir ${WORK_DIR} \
   --outfile-prefix "rfibp" ${WATERFALL1_PATHS[*]}
report_resumecmd

# Move the remaining results files to the specified results directory, if it is different from the
# working directory.
if [[ "${WORK_DIR}" != "${RESULTS_DIR}" ]]; then
   resumecmd -l ${LBL_RESULTS} -k ${RESUME_LASTCMD_SUCCESS} \
      transfer_files --src-dir "${WORK_DIR}" --dest-dir "${RESULTS_DIR}" \
      "*.png" "rfibp*.npy"
   report_resumecmd
fi

exit 0
