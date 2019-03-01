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
LOWER_FFT0=0
UPPER_FFT0=4094
LOWER_FFT1=0
UPPER_FFT1=4094
BP_WINDOW=10
BL_WINDOW=50
ENABLE_HANN=            # Set to "--enable-hann" to enable Hann window on raw data during reduction.
DATA_UTILIZE=1.0        # Fraction of raw data to use.  Positive values align to the beginning of the 
                        # raw data, while negative values align to the end.

# Configure file management parameters.
INSTALL_DIR="${HOME}/local/radiotrans"
WORK_DIR="/mnt/toaster/cyancey/${LABEL}"
RESULTS_DIR="${HOME}/analysis/${LABEL}"
SKIP_TRANSFER=0
DELWATERFALLS_OPT=
SKIP_TAR_OPT=
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
            LOWER_FFT0=100
            UPPER_FFT0=3200
            LOWER_FFT1=500
            UPPER_FFT1=2000
            BP_WINDOW=10
            BL_WINDOW=50

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
            SKIP_TRANSFER=1
            shift
            ;;
         --skip-tar) # Skip building tar file of results.
            SKIP_TAR_OPT="--skip-tar"
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
if [ ! -f "${DATA_PATH}" ]; then
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
      --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${DELWATERFALLS_OPT} )

# Perform the data reduction phase.
${CMD_REDUCE} ${CMD_REDUCE_OPTS[*]} "${DATA_PATH}"

if [ ${?} -eq 0 ]; then
   # Obtain FFT indices and smoothing window parameters from the user.
   LFFT0_STR="Lower FFT Index Tuning 0"
   UFFT0_STR="Upper FFT Index Tuning 0"
   LFFT1_STR="Lower FFT Index Tuning 1"
   UFFT1_STR="Upper FFT Index Tuning 1"
   BPW_STR="Bandpass smoothing window"
   BLW_STR="Baseline smoothing window"
   MENU_CHOICES=("yes" "no")
   echo "radiofilter.sh: User is advised to examine bandpass, baseline, and spectrogram plots "
   echo "to determine appropriate FFT index bound and smoothing window parameters before"
   echo "proceeding to the next phase."
   sleep 5
   echo "radiofilter.sh: Proceeding to RFI-bandpass filtration."
   echo "   ${LFFT0_STR} = ${LOWER_FFT0}"
   echo "   ${UFFT0_STR} = ${UPPER_FFT0}"
   echo "   ${LFFT1_STR} = ${LOWER_FFT1}"
   echo "   ${UFFT1_STR} = ${UPPER_FFT1}"
   echo "   ${BPW_STR} = ${BP_WINDOW}"
   echo "   ${BLW_STR} = ${BL_WINDOW}"
   echo "radiofilter.sh: Proceed with the above parameters?"
   PS3="Enter option number (1 or 2): "
   select USER_ANS in ${MENU_CHOICES[*]}
   do
      if [[ "${USER_ANS}" == "yes" ]]; then
         echo "radiofilter.sh: Proceding with RFI-bandpass filtration workflow..."
         break
      elif [[ "${USER_ANS}" == "no" ]]; then
         MENU_CHOICES=("${LFFT0_STR}" "${UFFT0_STR}" \
                        "${LFFT1_STR}" "${UFFT1_STR}" \
                        "${BPW_STR}" "${BLW_STR}" "Done")
         PS3="Select parameter to change (1, 2, 3, 4, 5, 6, or 7): "
         select USER_ANS in ${MENU_CHOICES[*]}
         do
            case "${USER_ANS}" in
               "${LFFT0_STR}" | \
               "${UFFT0_STR}" | \
               "${LFFT1_STR}" | \
               "${UFFT1_STR}" | \
               "${BPW_STR}" | \
               "${BLW_STR}" )
                  echo "Enter integer value: "
                  read USER_VAL
                  if [[ "${USER_VAL}" =~ ${INTEGER_NUM} ]]; then
                     case "${USER_ANS}" in
                        "${LFFT0_STR}" )
                           if [[ ${USER_VAL} > -1 ]] && [[ ${USER_VAL} < 4095 ]]; then
                              LOWER_FFT0=${USER_VAL}
                              break
                           else
                              echo "Entered value must be an integer from 0 to 4094"
                              continue
                           fi
                           ;;
                        "${UFFT0_STR}" )
                           if [[ ${USER_VAL} > -1 ]] && [[ ${USER_VAL} < 4095 ]]; then
                              UPPER_FFT0=${USER_VAL}
                              break
                           else
                              echo "Entered value must be an integer from 0 to 4094"
                              continue
                           fi
                           ;;
                        "${LFFT1_STR}" )
                           if [[ ${USER_VAL} > -1 ]] && [[ ${USER_VAL} < 4095 ]]; then
                              LOWER_FFT1=${USER_VAL}
                              break
                           else
                              echo "Entered value must be an integer from 0 to 4094"
                              continue
                           fi
                           ;;
                        "${UFFT1_STR}" )
                           if [[ ${USER_VAL} > -1 ]] && [[ ${USER_VAL} < 4095 ]]; then
                              UPPER_FFT1=${USER_VAL}
                              break
                           else
                              echo "Entered value must be an integer from 0 to 4094"
                              continue
                           fi
                           ;;
                        "${BPW_STR}" )
                           if [[ ${USER_VAL} > 0 ]]; then
                              BP_WINDOW=${USER_VAL}
                              break
                           else
                              echo "Entered value must be an integer greater than 0"
                              continue
                           fi
                           ;;
                        "${BLW_STR}" )
                           if [[ ${USER_VAL} > 0 ]]; then
                              BL_WINDOW=${USER_VAL}
                              break
                           else
                              echo "Entered value must be an integer greater than 0"
                              continue
                           fi
                     esac
                  else
                     echo "Entered value must be an integer. "
                     continue
                  fi
                  ;;
               "Done" )
                  MENU_CHOICES=("yes" "no")
                  echo "radiofilter.sh: Proceeding to RFI-bandpass filtration."
                  echo "   ${LFFT0_STR} = ${LOWER_FFT0}"
                  echo "   ${UFFT0_STR} = ${UPPER_FFT0}"
                  echo "   ${LFFT1_STR} = ${LOWER_FFT1}"
                  echo "   ${UFFT1_STR} = ${UPPER_FFT1}"
                  echo "   ${BPW_STR} = ${BP_WINDOW}"
                  echo "   ${BLW_STR} = ${BL_WINDOW}"
                  echo "radiofilter.sh: Proceed with the above parameters?"
                  PS3="Enter option number (1 or 2): "
                  break
                  ;;
               *)
                  continue
                  ;;
            esac
         done
      else
         continue
      fi
   done
   # Build the command-line to perform the RFI-bandpass filtration.
   CMD_FILTER="${INSTALL_DIR}/radiofilter.sh"
   CMD_FILTER_OPTS=(--install-dir "${INSTALL_DIR}" \
         --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} \
         --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
         --label "${LABEL}" --results-dir "${RESULTS_DIR}" \
         --lower-fft-index0 ${LOWER_FFT0} --upper-fft-index0 ${UPPER_FFT0} \
         --lower-fft-index1 ${LOWER_FFT1} --upper-fft-index1 ${UPPER_FFT1} \
         --bandpass-window ${BP_WINDOW} --baseline-window ${BL_WINDOW})
   # Perform the RFI-bandpass filtration.
   ${CMD_FILTER} ${CMD_FILTER[*]}
fi

if [ ${?} -eq 0 -a ${SKIP_TRANSFER} -eq 0 ]; then
   # Build the command-line to perform the file transfer to the results directory.
   CMD_TRANSFER="${INSTALL_DIR}/radiotransfer.sh"
   CMD_TRANSFER_OPTS=(--install-dir "${INSTALL_DIR}" --integrate-time ${INTEGTIME} \
         --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} ${ENABLE_HANN} \
         --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
         --decimation ${DECIMATION} --rfi-std-cutoff ${RFI_STD} --snr-cutoff ${SNR_CUTOFF} \
         --data-utilization ${DATA_UTILIZE} \
         --savitzky-golay0 "${SG_PARAMS0[*]}" --savitzky-golay1 "${SG_PARAMS1[*]}" \
         --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${DELWATERFALLS_OPT})
   # Perform transfer of results to results directory and build tar of results.
   ${CMD_TRANSFER} ${CMD_TRANSFER_OPTS[*]}
fi

exit ${?}
