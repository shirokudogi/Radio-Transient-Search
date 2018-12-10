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

DATA_PATH=           # Path to the raw radio data file.
WATERFALL_DIR=       # Paths to directory containing waterfall files.
WATERFALL0_PATHS=    # Paths to the tuning 0 waterfall files.
WATERFALL1_PATHS=    # Paths to the tuning 1 waterfall files.
COARSE0_FILE=        # Path to the tuning 0 spectrogram file.
COARSE1_FILE=        # Path to the tuning 1 spectrogram file.
WORK_DIR=            # Working directory.
RESULTS_DIR=         # Results directory.
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
         -0 | --coarse0-file) # Specify path to the tuning 0 coarse spectrogram file.
            if [ -z "${COARSE0_FILE}" ]; then
               COARSE0_FILE=${2}
            fi
            shift; shift
            ;;
         -1 | --coarse1-file) # Specify path to the tuning 0 coarse spectrogram file.
            if [ -z "${COARSE1_FILE}" ]; then
               COARSE1_FILE=${2}
            fi
            shift; shift
            ;;
         -d | --waterfall-dir) # Specify path to directory containing waterfall files.
            if [ -z "${WATERFALL_DIR}" ]; then
               WATERFALL_DIR="${2}"
            fi
            shift; shift
            ;;
         -*) # Unknown option
            echo "WARNING: radiofilter.sh -> Unknown option"
            echo "     ${1}"
            echo "Ignored: may cause option and argument misalignment."
            shift 
            ;;
         *) # Get the file paths.
            if [ -z "${DATA_PATH}" ]; then
               DATA_PATH="${1}"
            else
               WATERFALL_PATHS=(${WATERFALL_PATHS[*]} ${1})
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


# Check that specified install path exists and that all necessary components are contained.
if [ -z "${INSTALL_PATH}" ]; then
   INSTALL_PATH="."
fi
if [ -d "${INSTALL_PATH}" ]; then
   package_modules=(drx.py dp.py errors.py bandpasscheck.py watchwaterfall.py rfi.py 
                     apputils.py resume.sh utils.sh)
   for module in ${package_modules[*]}; do
      MODULE_PATH="${INSTALL_PATH}/${module}"
      if [ ! -f "${MODULE_PATH}" ]; then
         echo "ERROR: radiofilter.sh -> Missing package module"
         echo "     ${MODULE_PATH}"
         exit 1
      fi
   done
else
   echo "ERROR: radiofilter.sh -> Install path does not exist"
   echo "     ${INSTALL_PATH}"
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

# Check that the waterfall files directory exists.
if [ -z "${WATERFALL_DIR}" ]; then
   WATERFALL_DIR="${WORK_DIR}"
fi
if [ ! -d "${WATERFALL_DIR}" ]; then
   echo "ERROR: radioreduce.sh -> Waterfall file directory path not found"
   echo "     ${WATERFALL_DIR}"
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

# Check that the coarse spectrogram files exist.
if [ -z "${COARSE0_FILE}" ]; then
   COARSE0_FILE="${WORK_DIR}/coarsespectrogram-T0.npy"
fi
if [ ! -f "${COARSE0_FILE}" ]; then
   echo "ERROR: radiofilter.sh -> cannot find tuning 0 coarse spectrogram file."
   echo "     ${COARSE0_FILE}"
   exit 1
fi
if [ -z "${COARSE1_FILE}" ]; then
   COARSE1_FILE="${WORK_DIR}/coarsespectrogram-T1.npy"
fi
if [ ! -f "${COARSE1_FILE}" ]; then
   echo "ERROR: radiofilter.sh -> cannot find tuning 1 coarse spectrogram file."
   echo "     ${COARSE1_FILE}"
   exit 1
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
resumevar -l ${LBL_TUNE0FCH} TUNE0_FCH 4095      # Upper FFT index for the low tuning frequency.
resumevar -l ${LBL_TUNE1FCL} TUNE1_FCL 0       # Lower FFT index for the high tuning frequency.
resumevar -l ${LBL_TUNE1FCH} TUNE1_FCH 4095    # Upper FFT index for the high tuning frequency.

FLAG_CONTINUE=1
# Before we try to view the bandpass spectrograms, we need to pause the workflow here because the user
# may or may not be online when we get to this point, and the user may or may not have an X11 server and
# X11 forwarding setup.  Pausing here will give the user a chance to get online and perform any
# necessary setup to view the bandpass plots before moving to the next phase.
echo
echo "    The next phase involves adjusting the bandpass filtering for RFI.  Plots of the bandpass"
echo "    intensity and the spectrogram are generated, and the user can elect to have the plots be"
echo "    displayed from within the workflow (requires X11 and X11 forwarding, if working remotely);"
echo "    however, if this workflow is being run in the background with the user not in attendance,"
echo "    it is recommended that the plots not be displayed through the workflow and that the user"
echo "    use a utility like 'display' or 'imagemagick' to display the plot files (lowbandpass.png,"
echo "    highbandpass.png, lowspectrogram.png, highspectrogram.png"
echo
echo "    Display plots from within the workflow (requires X11 and X11 forwarding)? [y/n] "
read USER_ANSWER
USE_PLOTS=$(echo "${USER_ANSWER}" | tr '[:upper:]' '[:lower:]')
RESUME_FORCE_OPT=
while [[ ${FLAG_CONTINUE} -eq 1 ]]
do
   FLAG_CONTINUE=0
   echo
   echo "     Current FFT bandpass settings:"
   echo "         Low tuning lower index = ${TUNE0_FCL}"
   echo "         Low tuning upper index = ${TUNE0_FCH}"
   echo "         High tuning lower index = ${TUNE1_FCL}"
   echo "         High tuning upper index = ${TUNE1_FCH}"
   echo
   echo "    Generate plots to visualize bandpass? [y/n]"
   read USER_ANSWER
   GEN_PLOTS=$(echo "${USER_ANSWER}" | tr '[:upper:]' '[:lower:]')

   # Generate feedback plots if selected by user.
   if [[ "${GEN_PLOTS}" =~ ${AFFIRMATIVE} ]]; then
      echo "    Generating bandpass plots..."
      resumecmd -l ${LBL_BANDPASS0} -k ${RESUME_LASTCMD_SUCCESS} -s ${RESUME_REPEAT} \
         mpirun -np 1 python ${INSTALL_PATH}/bandpasscheck.py --lower-cutoff ${TUNE0_FCL} \
          --upper-cutoff ${TUNE1_FCL} --outfile "bandpass-T0.png" \
          --work-dir ${WORK_DIR} "${COARSE0_FILE}"
      report_resumecmd
      resumecmd -l ${LBL_BANDPASS1} -k ${RESUME_LASTCMD_SUCCESS} -s ${RESUME_REPEAT} \
         mpirun -np 1 python ${INSTALL_PATH}/bandpasscheck.py --lower-cutoff ${TUNE0_FCH} \
         --upper-cutoff ${TUNE1_FCH} --outfile "bandpass-T1.png" \
         --work-dir ${WORK_DIR} "${COARSE1_FILE}"
      report_resumecmd

      echo "    Generating spectrogram plots..."
      resumecmd -l ${LBL_SPECTROGRAM0} -k ${RESUME_LASTCMD_SUCCESS} -s ${RESUME_REPEAT} \
         mpirun -np 1 python ${INSTALL_PATH}/watchwaterfall.py --lower-cutoff ${TUNE0_FCL} \
          --upper-cutoff ${TUNE1_FCL} --outfile "bpspectrogram-T0.png" \
          --work-dir ${WORK_DIR} "${COARSE0_FILE}"
      report_resumecmd
      resumecmd -l ${LBL_SPECTROGRAM0} -k ${RESUME_LASTCMD_SUCCESS} -s ${RESUME_REPEAT} \
         mpirun -np 1 python ${INSTALL_PATH}/watchwaterfall.py --lower-cutoff ${TUNE0_FCH} \
         --upper-cutoff ${TUNE1_FCH} --outfile "bpspectrogram-T1.png" \
         --work-dir ${WORK_DIR} "${COARSE1_FILE}"
      report_resumecmd

      # Display the plots if selected by the user.
      if [[ "${USE_PLOTS}" =~ ${AFFIRMATIVE} ]]; then 
         display "${WORK_DIR}/bandpass-T0.png" &
         display "${WORK_DIR}/bandpass-T1.png" &

         display "${WORK_DIR}/bpspectrogram-T0.png" &
         display "${WORK_DIR}/bpspectrogram-T1.png" &
      fi
   fi

   echo "     Do you wish to change the bandpass region? [y/n] "
   read USER_ANSWER
   USER_ANSWER=$(echo "${USER_ANSWER}" | tr '[:upper:]' '[:lower:]')
   if [[ "${USER_ANSWER}" =~ ${AFFIRMATIVE} ]]; then 
      echo "    Change low tuning bandpass? [y/n]"
      read USER_ANSWER
      USER_ANSWER=$(echo "${USER_ANSWER}" | tr '[:upper:]' '[:lower:]')
      if [[ "${USER_ANSWER}" =~ ${AFFIRMATIVE} ]]; then 
         echo "    Enter the lower FFT index for the low tuning (integer between 0 and 4095): "
         read USER_ANSWER
         resumevar -l ${LBL_TUNE0FCL} -f TUNE0_FCL ${USER_ANSWER}
         echo "    Enter the upper FFT index for the low tuning (integer between 0 and 4095): "
         read USER_ANSWER
         resumevar -l ${LBL_TUNE0FCH} -f TUNE0_FCH ${USER_ANSWER}
         FLAG_CONTINUE=1
         RESUME_FORCE_OPT="-f"
      fi

      # Change bandpass for high tuning, if desired.
      echo "    Change high tuning bandpass? [y/n]"
      read USER_ANSWER
      USER_ANSWER=$(echo "${USER_ANSWER}" | tr '[:upper:]' '[:lower:]')
      if [[ "${USER_ANSWER}" =~ ${AFFIRMATIVE} ]]; then 
         echo "    Enter the lower FFT index for the high tuning (integer between 0 and 4095): "
         read USER_ANSWER
         resumevar -l ${LBL_TUNE1FCL} -f TUNE1_FCL ${USER_ANSWER}
         echo "    Enter the upper FFT index for the high tuning (integer between 0 and 4095): "
         read USER_ANSWER
         resumevar -l ${LBL_TUNE1FCH} -f TUNE1_FCH ${USER_ANSWER}
         FLAG_CONTINUE=1
         RESUME_FORCE_OPT="-f"
      fi
   fi
done


# Extract information about the time-series for use in doing the de-dispersion and transient extraction
# with dv.py
COMMCONFIGFILE="${WORK_DIR}/radiotrans.ini"
echo "     Generating time-series information for de-dispersion..."
resumecmd -l ${LBL_FREQTINT} ${RESUME_FORCE_OPT} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_PATH}/freqtint.py "${DATA_PATH}" \
   --tune0-fftlow ${TUNE0_FCL} --tune0-ffthigh ${TUNE0_FCH} \
   --tune1-fftlow ${TUNE1_FCL} --tune1-ffthigh ${TUNE1_FCH} --work-dir ${WORK_DIR}
   --commconfig "${COMMCONFIGFILE}"
report_resumecmd

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

