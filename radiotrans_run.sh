#!/bin/bash

shopt -s extglob

# User input test patterns.
AFFIRMATIVE='^(y|yes|yup|yea|yeah|ya)$'
INTEGER_NUM='^[+-]?[0-9]+$'
REAL_NUM='^[+-]?[0-9]+([.][0-9]+)?$'


# Configure process parameters.
NUM_PROCS=$(nproc --all)   # Number of processes to use in the MPI environment.
MEM_LIMIT=32768            # Memory limit, in MBs, for creating waterfall tiles in memory.
RUN_STATUS=0
SKIP_RFIBP=0
SKIP_REDUCE=0
DO_DDISP_SEARCH=0
INDEX=0
SUPERCLUSTER_OPT=
NO_SEARCH_INTERACT_OPT=
NO_RFIBP_INTERACT_OPT=
NO_REDUCE_INTERACT_OPT=


# Configure main directories.
INSTALL_DIR=
WORK_ROOT=
RESULTS_ROOT=
DATA_DIR=

# Build list of data files and associated run labels
RUN_INDICES=
DATA_FILENAMES=
LABELS=

# Configure common radio run parameters to apply to all runs.
COMMCONFIG_FILE=
INTEGTIME=125        # In milliseconds.  Do not set this below 24.03265 ms to avoid corruption during 
                     # RFI filtering and data smoothing.
DECIMATION=10000
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
ENABLE_HANN_OPT=            # Set to "--enable-hann" to enable Hann window on raw data during reduction.
DATA_UTILIZE=           # Fraction of raw data to use.  Positive values align to the beginning of the 
                        # raw data, while negative values align to the end.
SNR_THRESHOLD=5.0
DM_START=30.0
DM_END=1800.0
MAX_PULSE_WIDTH=2.0

# Configure file management parameters.
SKIP_TRANSFER_OPT=
DELWATERFALLS_OPT=
SKIP_TAR_OPT=
RELOAD_WORK=0



# Select whether we are using the release install of radiotrans or still using the developer version to
# debug issues.
if [[ ${#} -gt 0 ]]; then
   while [ -n "${1}" ]
   do
      case "${1}" in
         --GW170817) # Perform pre-made run for GW170809.
            echo "radiotrans_run.sh: Using GW170809 search parameter set."

            # Configure common radio run parameters.
            INTEGTIME=100
            DECIMATION=10000
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
            SNR_THRESHOLD=5.0
            DM_START=30.0
            DM_END=1800.0
            MAX_PULSE_WIDTH=2.0

            shift
            ;;
         --CLEAGUE ) # Perform pre-made run for Cleague.
            echo "radiotrans_run.sh: Using CLEAGUE search parameter set."

            # Configure common radio run parameters.
            INTEGTIME=2089.80
            DECIMATION=4000
            RFI_STD=5.0
            SNR_CUTOFF=3.0
            SG_PARAMS0=(151 2 151 2)
            SG_PARAMS1=(111 2 151 2)
            LOWER_FFT0=0
            UPPER_FFT0=4094
            LOWER_FFT1=0
            UPPER_FFT1=4094
            BP_WINDOW=11
            BL_WINDOW=51
            SNR_THRESHOLD=5.0
            DM_START=30.0
            DM_END=1000.0
            MAX_PULSE_WIDTH=2.0

            shift
            ;;
         --DEBUG) # Run with debug search parameters.
            echo "radiotrans_run.sh: Using DEBUG search parameter set."

            # Configure common radio run parameters.
            INTEGTIME=500.0
            DECIMATION=4000
            RFI_STD=5.0
            SNR_CUTOFF=3.0
            SG_PARAMS0=(151 2 151 2)
            SG_PARAMS1=(111 2 151 2)
            ENABLE_HANN_OPT=
            LOWER_FFT0=0
            UPPER_FFT0=4094
            LOWER_FFT1=0
            UPPER_FFT1=4094
            BP_WINDOW=10
            BL_WINDOW=50
            SNR_THRESHOLD=5.0
            DM_START=30.0
            DM_END=1000.0
            MAX_PULSE_WIDTH=2.0

            shift
            ;;
         -I | --install-dir) # Set the install directory to the specified location.
            if [ -z "${INSTALL_DIR}" -a -d "${2}" ]; then
               INSTALL_DIR="${2}"
            else
               echo "Cannot find install directory ${2}"
            fi
            shift; shift
            ;;
         -W | --work-root) # Specify the root for working directories.
            if [ -d "${2}" ]; then
               WORK_ROOT="${2}"
            else
               echo "radiotrans_run.sh (ERROR): Working root directory ${2} does not exist."
               echo "User needs to create the root directory."
               exit 1
            fi
            shift; shift
            ;;
         -R | --results-root) # Specify the root for results directories.
            if [ -d "${2}" ]; then
               RESULTS_ROOT="${2}"
            else
               echo "radiotrans_run.sh (ERROR): Results root directory ${2} does not exist."
               echo "User needs to create the root directory."
               exit 1
            fi
            shift; shift
            ;;
         -D | --data-dir) # Specify the data directory.
            if [ -d "${2}" ]; then
               DATA_DIR="${2}"
            else
               echo "radiotrans_run.sh (ERROR): Data directory ${2} does not exist."
               echo "User needs to create the data directory."
               exit 1
            fi
            shift; shift
            ;;
         -A | --add-run) # Adds a run to the current set using the parameters that have been setup.
            if [ -n "${2}" ] && [ -n "${3}" ]; then
               LABELS=(${LABELS[*]} "${2}")
               DATA_FILENAMES=(${DATA_FILENAMES[*]} "${3}")
               RUN_INDICES=(${RUN_INDICES[*]} ${INDEX})
               INDEX=`expr ${INDEX} + 1`
               shift; shift; shift
            else
               echo "radiotrans_run.sh: Runs need to be specified with a label and associated data file"
               echo "                   within the data directory."
               exit 1
            fi
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
            SKIP_TRANSFER_OPT="--skip-transfer"
            shift
            ;;
         --skip-tar) # Skip building tar file of results.
            SKIP_TAR_OPT="--skip-tar"
            shift
            ;;
         --skip-rfi-bandpass) # Skip the RFI-bandpass filtration phase.
            SKIP_RFIBP=1
            shift
            ;;
         --skip-reduction) # Skip the data reduction stage.
            SKIP_REDUCE=1
            shift
            ;;
         --do-dedispersed-search) # Run the de-dispersed search here on LWA.
            DO_DDISP_SEARCH=1
            shift
            ;;
         --delete-waterfalls) # Delete waterfall file from the working directory at the end of the run.
            DELWATERFALLS_OPT="--delete-waterfalls"
            shift
            ;;
         --enable-hann) # Enable Hann windowing on waterfalls.
            ENABLE_HANN_OPT="--enable-hann"
            shift
            ;;
         --reload-work) # Reload key results from the results directory to the work directory and then
                        # rerun the workflow.
            RELOAD_WORK=1
            shift
            ;;
         --supercluster) # Specify workflow is running on the V-Tech supercluster.
            SUPERCLUSTER_OPT="--supercluster"
            shift
            ;;
         --no-reduce-interact)
            NO_REDUCE_INTERACT_OPT="--no-interact"
            shift
            ;;
         --no-rfibp-interact)
            NO_RFIBP_INTERACT_OPT="--no-interact"
            shift
            ;;
         --no-search-interact)
            NO_SEARCH_INTERACT_OPT="--no-interact"
            shift
            ;;
         --no-interact)
            NO_SEARCH_INTERACT_OPT="--no-interact"
            NO_RFIBP_INTERACT_OPT="--no-interact"
            NO_REDUCE_INTERACT_OPT="--no-interact"
            shift
            ;;
         *) # Ignore anything else.
            shift
            ;;
      esac
   done
fi

# Check that we have something to do.
if [ -z "${RUN_INDICES[*]}" ]; then
   echo "radiotrans_run.sh: No runs specified to do."
   exit 1
fi

# Ensure the data utilization value is set.
if [ -z "${DATA_UTILIZE}" ]; then
   DATA_UTILIZE=1.0
fi

# Check for the install directory and module dependencies.
if [ -z "${INSTALL_DIR}" ]; then
   INSTALL_DIR="OPT-INSTALL_DIR"
fi
if [ -d "${INSTALL_DIR}" ]; then
   package_modules=(radioreduce.sh radiofilter.sh radiotransfer.sh radiosearch.sh)
   for module in ${package_modules[*]}; do
      MODULE_PATH="${INSTALL_DIR}/${module}"
      if [ ! -f "${MODULE_PATH}" ]; then
         echo "ERROR: radiotrans_run.sh -> Missing package module"
         echo "     ${MODULE_PATH}"
         exit 1
      fi
   done
else
   echo "ERROR: radiotrans_run.sh -> Install path does not exist"
   echo "     ${INSTALL_DIR}"
   exit 1
fi

# Check that the working root directories is specified.
if [ -z "${WORK_ROOT}" ]; then
   echo "radiotrans_run.sh: Working root directory needs to be specified by user."
   exit 1
else
   if [ ! -d "${WORK_ROOT}" ]; then
      mkdir -p "${WORK_ROOT}"
      if [ ! -d "${WORK_ROOT}" ]; then
         echo "radiotrans_run.sh: Could not create working root directory ${WORK_ROOT}"
         exit 1
      fi
   fi
fi

# Check that the working root directories is specified.
if [ -z "${RESULTS_ROOT}" ]; then
   echo "radiotrans_run.sh: Results root directory not specified by user."
   echo "                   Using working root directory as results root directory."
   RESULTS_ROOT="${WORK_ROOT}"
else
   if [ ! -d "${RESULTS_ROOT}" ]; then
      mkdir -p "${RESULTS_ROOT}"
      if [ ! -d "${RESULTS_ROOT}" ]; then
         echo "radiotrans_run.sh: Could not create results root directory ${RESULTS_ROOT}"
         echo "                   Using working root directory as results root directory."
         RESULTS_ROOT="${WORK_ROOT}"
      fi
   fi
fi

# Check that the data directory is specified if we are doing a data reduction.
if [ -z "${DATA_DIR}" ] && [ ${SKIP_REDUCE} -eq 0 ]; then
   echo "radiotrans_run.sh: Data directory needs to be specified by user when doing data reduction."
   exit 1
fi

ALL_STATUS=0
for INDEX in ${RUN_INDICES[*]}
do
   RUN_STATUS=0

   # Create the run label, path to data, working directory path, and results directory path for current
   # run iteration.
   LABEL="${LABELS[${INDEX}]}"
   DATA_PATH="${DATA_DIR}/${DATA_FILENAMES[${INDEX}]}"
   WORK_DIR="${WORK_ROOT}/${LABEL}"
   RESULTS_DIR="${RESULTS_ROOT}/${LABEL}"
   COMMCONFIG_FILE="config_${LABEL}.ini"

   # Ensure the data file exists.
   if [ ! -f "${DATA_PATH}" ] && [ ${SKIP_REDUCE} -eq 0 ]; then
      echo "radiotrans_run.sh: ERROR => Data file ${DATA_PATH} not found."
      RUN_STATUS=1
   fi

   # Create the working directory, if it doesn't exist.
   if [ ! -d "${WORK_DIR}" ]; then
      mkdir -p "${WORK_DIR}"
      if [ ! -d "${WORK_DIR}" ]; then
         echo "Could not create working directory ${WORK_DIR}"
         RUN_STATUS=1
      fi
   fi

   # Create the results directory, if it doesn't exist.
   if [ ! -d "${RESULTS_DIR}" ]; then
      mkdir -p "${RESULTS_DIR}"
      if [ ! -d "${RESULTS_DIR}" ]; then
         echo "Could not create results directory ${RESULTS_DIR}"
         RUN_STATUS=1
      fi
   fi


   # Stage to reload work into the working directory.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${RELOAD_WORK} -eq 1 ]; then
      # Build the command-line to perform the file transfer to the working directory from results
      # directory.
      CMD_TRANSFER="${INSTALL_DIR}/radiotransfer.sh"
      CMD_TRANSFER_OPTS=(--install-dir "${INSTALL_DIR}" \
            --work-dir "${WORK_DIR}" --label "${LABEL}" --results-dir "${RESULTS_DIR}"  \
            --reload-work ${SUPERCLUSTER_OPT})
      # Perform transfer of file to working directory from results directory.
      ${CMD_TRANSFER} ${CMD_TRANSFER_OPTS[*]}
      RUN_STATUS=${?}
   fi

   # Stage to reduce radio data.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${SKIP_REDUCE} -eq 0 ]; then
      # Build the command-line to perform data reduction.
      CMD_REDUCE="${INSTALL_DIR}/radioreduce.sh"
      CMD_REDUCE_OPTS=(--install-dir "${INSTALL_DIR}" --integrate-time ${INTEGTIME} \
            --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} ${ENABLE_HANN_OPT} \
            --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
            --decimation ${DECIMATION} --rfi-std-cutoff ${RFI_STD} --snr-cutoff ${SNR_CUTOFF} \
            --data-utilization ${DATA_UTILIZE} ${SUPERCLUSTER_OPT} ${NO_REDUCE_INTERACT_OPT} \
            --savitzky-golay0 "${SG_PARAMS0[*]}" --savitzky-golay1 "${SG_PARAMS1[*]}" \
            --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${DELWATERFALLS_OPT})

      # Perform the data reduction phase.
      ${CMD_REDUCE} ${CMD_REDUCE_OPTS[*]} "${DATA_PATH}"
      RUN_STATUS=${?}
   fi

   # Stage to perform RFI-bandpass filtration.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${SKIP_RFIBP} -eq 0 ]; then
      echo "radiofilter.sh: User is advised to examine bandpass, baseline, and spectrogram plots "
      echo "to determine appropriate FFT index bound and smoothing window parameters before"
      echo "proceeding to the next phase."
      echo
      sleep 3

      # Obtain FFT indices and smoothing window parameters from the user.
      LFFT0_STR="Lower_FFT_Index_Tuning_0"
      UFFT0_STR="Upper_FFT_Index_Tuning_0"
      LFFT1_STR="Lower_FFT_Index_Tuning_1"
      UFFT1_STR="Upper_FFT_Index_Tuning_1"
      BPW_STR="Bandpass_smoothing_window"
      BLW_STR="Baseline_smoothing_window"
      MENU_BREAK=0
      echo "radiofilter.sh: Proceeding to RFI-bandpass filtration."
      while [ ${MENU_BREAK} -eq 0 ]
      do
         MENU_CHOICES=("yes" "no" "quit")
         echo "   Lower FFT Index Tuning 0 = ${LOWER_FFT0}"
         echo "   Upper FFT Index Tuning 0 = ${UPPER_FFT0}"
         echo "   Lower FFT Index Tuning 1 = ${LOWER_FFT1}"
         echo "   Upper FFT Index Tuning 1 = ${UPPER_FFT1}"
         echo "   Bandpass smoothing window = ${BP_WINDOW}"
         echo "   Baseline smoothing window = ${BL_WINDOW}"

         # Skip interaction if requested by user...
         if [ -n "${NO_RFIBP_INTERACT_OPT}" ]; then
            # Build the command-line to perform the RFI-bandpass filtration.
            CMD_FILTER="${INSTALL_DIR}/radiofilter.sh"
            CMD_FILTER_OPTS=(--install-dir "${INSTALL_DIR}" \
                  --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} --no-interact \
                  --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
                  --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${SUPERCLUSTER_OPT} \
                  --lower-fft-index0 ${LOWER_FFT0} --upper-fft-index0 ${UPPER_FFT0} \
                  --lower-fft-index1 ${LOWER_FFT1} --upper-fft-index1 ${UPPER_FFT1} \
                  --bandpass-window ${BP_WINDOW} --baseline-window ${BL_WINDOW})
            # Perform the RFI-bandpass filtration.
            ${CMD_FILTER} ${CMD_FILTER_OPTS[*]}
            RUN_STATUS=${?}
            
            MENU_BREAK=1
            break
         fi

         # ...otherwise, proceed with interaction.
         echo "radiofilter.sh: Proceed with the above parameters?"
         PS3="Select option: "
         select USER_SELECT in ${MENU_CHOICES[*]}
         do
            if [[ "${USER_SELECT}" == "yes" ]]; then
               # Run the RFI-bandpass filtration.
               echo "radiofilter.sh: Proceding with RFI-bandpass filtration workflow..."
               echo
               # Build the command-line to perform the RFI-bandpass filtration.
               CMD_FILTER="${INSTALL_DIR}/radiofilter.sh"
               CMD_FILTER_OPTS=(--install-dir "${INSTALL_DIR}" \
                     --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} --no-interact \
                     --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
                     --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${SUPERCLUSTER_OPT} \
                     --lower-fft-index0 ${LOWER_FFT0} --upper-fft-index0 ${UPPER_FFT0} \
                     --lower-fft-index1 ${LOWER_FFT1} --upper-fft-index1 ${UPPER_FFT1} \
                     --bandpass-window ${BP_WINDOW} --baseline-window ${BL_WINDOW})
               # Perform the RFI-bandpass filtration.
               ${CMD_FILTER} ${CMD_FILTER_OPTS[*]}
               RUN_STATUS=${?}

               MENU_BREAK=1
               break
            elif [[ "${USER_SELECT}" == "quit" ]]; then
               # Quit from RFI-bandpass filtration.
               echo "radiotrans_run.sh: Quitting from RFI-bandpass filtration."
               RUN_STATUS=1
               MENU_BREAK=1
               break
            elif [[ "${USER_SELECT}" == "no" ]]; then
               # Get new parameters for RFI-bandpass filtration from user.
               MENU_CHOICES=("${LFFT0_STR}" "${UFFT0_STR}" \
                              "${LFFT1_STR}" "${UFFT1_STR}" \
                              "${BPW_STR}" "${BLW_STR}" "Done")
               PS3="Select parameter to change: "
               select USER_SELECT in ${MENU_CHOICES[*]}
               do
                  case "${USER_SELECT}" in
                     "${LFFT0_STR}" | \
                     "${UFFT0_STR}" | \
                     "${LFFT1_STR}" | \
                     "${UFFT1_STR}" | \
                     "${BPW_STR}" | \
                     "${BLW_STR}" )
                        while [ 1 ] 
                        do
                           echo "Enter integer value: "
                           read USER_VAL
                           if [[ "${USER_VAL}" =~ ${INTEGER_NUM} ]]; then
                              case "${USER_SELECT}" in
                                 "${LFFT0_STR}" )
                                    if [ ${USER_VAL} -gt -1 ] && [ ${USER_VAL} -lt 4095 ]; then
                                       LOWER_FFT0=${USER_VAL}
                                       break
                                    else
                                       echo "Entered value must be an integer from 0 to 4094"
                                    fi
                                    ;;
                                 "${UFFT0_STR}" )
                                    if [ ${USER_VAL} -gt -1 ] && [ ${USER_VAL} -lt 4095 ]; then
                                       UPPER_FFT0=${USER_VAL}
                                       break
                                    else
                                       echo "Entered value must be an integer from 0 to 4094"
                                    fi
                                    ;;
                                 "${LFFT1_STR}" )
                                    if [ ${USER_VAL} -gt -1 ] && [ ${USER_VAL} -lt 4095 ]; then
                                       LOWER_FFT1=${USER_VAL}
                                       break
                                    else
                                       echo "Entered value must be an integer from 0 to 4094"
                                    fi
                                    ;;
                                 "${UFFT1_STR}" )
                                    if [ ${USER_VAL} -gt -1 ] && [ ${USER_VAL} -lt 4095 ]; then
                                       UPPER_FFT1=${USER_VAL}
                                       break
                                    else
                                       echo "Entered value must be an integer from 0 to 4094"
                                    fi
                                    ;;
                                 "${BPW_STR}" )
                                    if [ ${USER_VAL} -gt 0 ]; then
                                       BP_WINDOW=${USER_VAL}
                                       break
                                    else
                                       echo "Entered value must be an integer greater than 0"
                                    fi
                                    ;;
                                 "${BLW_STR}" )
                                    if [ ${USER_VAL} -gt 0 ]; then
                                       BL_WINDOW=${USER_VAL}
                                       break
                                    else
                                       echo "Entered value must be an integer greater than 0"
                                    fi
                              esac
                           else
                              echo "Entered value must be an integer. "
                           fi
                        done # endwhile
                        break
                        ;;
                     Done)
                        break
                        ;;
                     *)
                        continue
                        ;;
                  esac
               done # endselect 
               break
            else
               continue
            fi
         done # endselect
      done # endwhile
   else
      if [ ${RUN_STATUS} -eq 0 ] && [ ${SKIP_RFIBP} -eq 1 ]; then
         echo "radiotrans_run.sh: Skipping RFI-bandpass filtration per user request."
         echo
      fi
   fi

   # Stage to perform de-dispered search.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${DO_DDISP_SEARCH} -eq 1 ]; then
      CMBPREFIX="spectrogram"
      if [ -n "${LABEL}" ]; then
         CMBPREFIX="${CMBPREFIX}_${LABEL}"
      fi
      if [ ! -f "${WORK_DIR}/rfibp-${CMBPREFIX}-T0.npy" ]; then
         echo "radiotrans_run.sh: Missing T0 RFI-bandpass filtered spectrogram."
         echo "                 Copying T0 unfiltered spectrogram as RFI-bandpass filtered."
         echo
         cp "${WORK_DIR}/${CMBPREFIX}-T0.npy" "${WORK_DIR}/rfibp-${CMBPREFIX}-T0.npy"
      fi

      if [ ! -f "${WORK_DIR}/rfibp-${CMBPREFIX}-T1.npy" ]; then
         echo "radiotrans_run.sh: Missing T1 RFI-bandpass filtered spectrogram."
         echo "                 Copying T1 unfiltered spectrogram as RFI-bandpass filtered."
         echo
         cp "${WORK_DIR}/${CMBPREFIX}-T1.npy" "${WORK_DIR}/rfibp-${CMBPREFIX}-T1.npy"
      fi
      # Build the command-line to perform the de-dispersed search.
      CMD_SEARCH="${INSTALL_DIR}/radiosearch.sh"
      CMD_SEARCH_OPTS=(--install-dir "${INSTALL_DIR}" ${SUPERCLUSTER_OPT} \
            --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} ${NO_SEARCH_INTERACT_OPT} \
            --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
            --label "${LABEL}" --results-dir "${RESULTS_DIR}" \
            --dm-start ${DM_START} --dm-end ${DM_END} \
            --snr-threshold ${SNR_THRESHOLD} --max-pulse-width ${MAX_PULSE_WIDTH})
      # Perform the RFI-bandpass filtration.
      ${CMD_SEARCH} ${CMD_SEARCH_OPTS[*]}
      RUN_STATUS=${?}
   fi

   # Stage to transfer results to results directory and tar up results.
   if [ ${RUN_STATUS} -eq 0 ]; then
      # Build the command-line to perform the file transfer to the results directory and build tar file.
      CMD_TRANSFER="${INSTALL_DIR}/radiotransfer.sh"
      CMD_TRANSFER_OPTS=(--install-dir "${INSTALL_DIR}" ${SUPERCLUSTER_OPT} \
            --work-dir "${WORK_DIR}" --label "${LABEL}" --results-dir "${RESULTS_DIR}" 
            ${SKIP_TRANSFER_OPT} ${SKIP_TAR_OPT})
      # Perform transfer of results to results directory and build tar of results.
      ${CMD_TRANSFER} ${CMD_TRANSFER_OPTS[*]}
      RUN_STATUS=${?}
   fi

   # Report workflow execution status to user.
   if [ ${RUN_STATUS} -eq 0 ]; then
      echo "radiotrans_run.sh: All workflow phases executed successfully!"
      echo
   else
      echo "radiotrans_run.sh: Some phases of the workflow failed or could not be executed due to"
      echo "                 prior failures.  Additional debug/investigation may be needed :("
      echo "   LABEL = ${LABEL}"
      echo "   DATA_FILE = ${DATA_PATH}"
      echo "   WORK_DIR = ${WORK_DIR}"
      echo "   RESULTS_DIR = ${RESULTS_DIR}"
      echo
      ALL_STATUS=1
   fi
done

if [ ${ALL_STATUS} -eq 0 ]; then
   echo "radiotrans_run.sh: All iterations of the workflow executed successfully!"
   echo
else
   echo "radiotrans_run.sh: Some iterations of the workflow failed"
   echo
fi
exit ${ALL_STATUS}
