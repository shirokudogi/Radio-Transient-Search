#!/bin/bash
#
# radiotrans_run.sh
#
# PURPOSE: Main entry script to run the entirety of the Radio Transient Search workflow, originally
#          developed by Jamie Tsai and improved by Cregg C. Yancey.
#

shopt -s extglob

source "OPT-INSTALL_DIR/text_patterns.sh"
#source "${HOME}/dev/radiotrans/text_patterns.sh"   # Use only when debugging.




# Pause menu options.
PAUSE_OPT_PAUSE="Pause"
PAUSE_OPT_RESUME="Resume"
PAUSE_OPT_CLEAN="Clean"
PAUSE_OPT_CONTINUE="Continue"
PAUSE_OPT_STOP="Stop"
PAUSE_OPT_PAUSEALL="Pause All"
PAUSE_OPT_STOPALL="Stop All"
PAUSE_OPT_CONTINUEALL="Continue All"

# RFI-Bandpass menu options.
LFFT0_STR="Lower FFT Index Tuning 0"
UFFT0_STR="Upper FFT Index Tuning 0"
LFFT1_STR="Lower FFT Index Tuning 1"
UFFT1_STR="Upper FFT Index Tuning 1"
BPW_STR="Bandpass smoothing window"
BLW_STR="Baseline smoothing window"

# Process parameters.
MEM_LIMIT=32768            # Memory limit, in MBs, for creating waterfall tiles in memory.
RUN_STATUS=0
SKIP_RFIBP=0
SKIP_REDUCE=0
DO_DDISP_SEARCH=0
INDEX=0
DEFAULT_PARAMS=0
SUPERCLUSTER_OPT=
NO_SEARCH_INTERACT_OPT=
NO_RFIBP_INTERACT_OPT=
NO_REDUCE_INTERACT_OPT=
DATA_UTILIZE=

# File management parameters.
SKIP_TRANSFER_OPT=
DELWATERFALLS_OPT=
SKIP_TAR_OPT=
RELOAD_WORK=0
FORCE_TRANSFER_OPT=

# Main directories.
INSTALL_DIR=
WORK_ROOT=
RESULTS_ROOT=
DATA_DIR=

# Build list of data files and associated run labels
COMMCONFIG_FILE=
PARAMS_FILE=


# Select whether we are using the release install of radiotrans or still using the developer version to
# debug issues.
if [[ ${#} -gt 0 ]]; then
   while [ -n "${1}" ]
   do
      case "${1}" in
         --GW170809) # Perform pre-made run for GW170809.
            if [ ${DEFAULT_PARAMS} -eq 0 ]; then
               DEFAULT_PARAMS=1
            fi
            shift
            ;;
         --CLEAGUE ) # Perform pre-made run for Cleague.
            if [ ${DEFAULT_PARAMS} -eq 0 ]; then
               DEFAULT_PARAMS=2
            fi
            shift
            ;;
         --DEBUG) # Run with debug search parameters.
            if [ ${DEFAULT_PARAMS} -eq 0 ]; then
               DEFAULT_PARAMS=3
            fi
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
            if [ -n "${2}" ] && [ -n "${3}" ] && [ -n "${4}" ]; then
               if [ ${#LABELS[@]} -eq 0 ]; then
                  LABELS="${2}"
                  DATA_FILENAMES="${3}"
                  PARAMS_FILES="${4}"
               else
                  LABELS=("${LABELS[@]}" "${2}")
                  DATA_FILENAMES=("${DATA_FILENAMES[@]}" "${3}")
                  PARAMS_FILES=("${PARAMS_FILES[@]}" "${4}")
               fi
               shift; shift; shift; shift
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
         -N | --num-procs) # Specify the number of processes to use.
            if [ -z "${NUM_PROCS}" ]; then
               if [[ "${2}" =~ ${INTEGER_NUM} ]]; then
                  NUM_PROCS=${2}
               fi
            fi
            shift; shift
            ;;
         -U | --data-utilization) # Specify RFI standard deviation cutoff.
            if [ -z "${DATA_UTILIZE}" ]; then
               if [[ "${2}" =~ ${REAL_NUM} ]]; then
                  DATA_UTILIZE="${2}"
               fi
            fi
            shift; shift
            ;;
         -P | --parameters-file) # Specify the run parameters file from which to read run parameters.
            if [ -z "${PARAMS_FILE}" ]; then
               PARAMS_FILE="${2}"
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
         --skip-reduce) # Skip the data reduction stage.
            SKIP_REDUCE=1
            shift
            ;;
         --do-dedispersed-search) # Run the de-dispersed search here on LWA.
            DO_DDISP_SEARCH=1
            shift
            ;;
         --disable-rfi-filter) # Disable RFI filtering.
            DISABLE_RFI_OPT="--disable-rfi-filter"
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
            FORCE_TRANSFER_OPT="--force-repeat"
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
         --no-time-average) # Specify to just do the time integration without taking the time-average
                            # afterwards during the data reduction phase.
            if [ -z "${NO_TIME_AVG_OPT}" ]; then
               NO_TIME_AVG_OPT="--no-time-average"
            fi
            shift
            ;;
         --clean) # Clear the working and results directories and restart the run from scratch.
            CLEAN_RUN=1
            shift
            ;;
         --destroy) # Destroy the run.
            DESTROY_RUN="DO IT!"
            shift
            ;;
         --play-nice) # Specify that the run should play nice with it's execution and use of computing
                      # resources. This essentially amounts to having points at which the user can save
                      # work progress and continue it later, even on a different node in the cluster.
            PLAY_NICE_OPT="DO IT!"
            shift
            ;;
         *) # Ignore anything else.
            shift
            ;;
      esac
   done
fi

# Check that we have something to do.
if [ ${#LABELS[@]} -eq 0 ]; then
   echo "radiotrans_run.sh: No runs specified to do."
   exit 1
fi

# Check that number of processors to use is specified.
if [ -z "${NUM_PROCS}" ]; then
   NUM_PROCS=$(nproc --all)   # Number of processes to use in the MPI environment.
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
   package_modules=(radioreduce.sh radiofilter.sh radiotransfer.sh radiosearch.sh utils.sh)
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
source "${INSTALL_DIR}/utils.sh"

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

source "${INSTALL_DIR}/utils.sh"


ALL_STATUS=0
for RUN_INDEX in ${!LABELS[@]}
do
   RUN_STATUS=0

   # Create the run label, path to data, working directory path, and results directory path for current
   # run iteration.
   LABEL="${LABELS[${RUN_INDEX}]}"
   DATA_PATH="${DATA_DIR}/${DATA_FILENAMES[${RUN_INDEX}]}"
   WORK_DIR="${WORK_ROOT}/${LABEL}"
   RESULTS_DIR="${RESULTS_ROOT}/${LABEL}"
   PARAMS_FILE="${PARAMS_FILES[${RUN_INDEX}]}"
   PAUSE_FILE="${RESULTS_DIR}/${LABEL}_paused_run"

   echo "radiotrans_run.sh: Executing run ${LABEL}=>"
   if [ -n "${LABEL}" ]; then
      COMMCONFIG_FILE="${LABEL}.comm"
   else
      COMMCONFIG_FILE="radiotrans.comm"
   fi

   # Destroy the run, if requested.
   if [ ! -z "${DESTROY_RUN}" ]; then
      echo "radiotrans_run.sh: Destroying run ${LABEL}"
      if [ -d "${WORK_DIR}" ]; then
         echo "     Destroying working directory ${WORK_DIR}"
         rm -rf "${WORK_DIR}"
      fi
      if [ -d "${RESULTS_DIR}" ]; then
         echo "     Destroying results directory ${RESULTS_DIR}"
         rm -rf "${RESULTS_DIR}"
      fi
      echo "radiotrans_run.sh: Run ${LABEL}=> DESTROYED!!!"
      continue
   fi

   # Ensure the data file exists.
   if [ ! -f "${DATA_PATH}" ] && [ ${SKIP_REDUCE} -eq 0 ]; then
      echo "radiotrans_run.sh: ERROR => Data file ${DATA_PATH} not found."
      RUN_STATUS=1
   fi

   # Create the working directory, if it doesn't exist.
   if [ ! -d "${WORK_DIR}" ]; then
      mkdir -p "${WORK_DIR}"
      if [ ! -d "${WORK_DIR}" ]; then
         echo "radiotrans_run.sh: Could not create working directory ${WORK_DIR}"
         RUN_STATUS=1
      fi
   else
      # If this is to be a clean run, then clear the working directory.
      if [ ! -z "${CLEAN_RUN}" ] && [ ${CLEAN_RUN} -eq 1 ]; then
         echo "radiotrans_run.sh: Cleaning working directory."
         rm -rf "${WORK_DIR}"
         mkdir -p "${WORK_DIR}"
         if [ ! -d "${WORK_DIR}" ]; then
            echo "radiotrans_run.sh: Could not recreate working directory ${WORK_DIR}"
            RUN_STATUS=1
         fi
      fi
   fi

   RESUMING_FROM_PAUSE=0
   # Create the results directory, if it doesn't exist.
   if [ ! -d "${RESULTS_DIR}" ]; then
      mkdir -p "${RESULTS_DIR}"
      if [ ! -d "${RESULTS_DIR}" ]; then
         echo "radiotrans_run.sh: Could not create results directory ${RESULTS_DIR}"
         RUN_STATUS=1
      fi
   else
      # If we're playing nicely with computing resources, check if this run is marked as 
      # being paused.
      if [ -f "${PAUSE_FILE}" ] && [ -n "${PLAY_NICE_OPT}" ]; then
         echo "radiotrans_run.sh: Run \"${LABEL}\" currently paused.  You have the option to leave" 
         echo "                   the run paused (option \"${PAUSE_OPT_PAUSE}\"), resume the run "
         echo "                   (option \"${PAUSE_OPT_RESUME}\"), restart with a clean run "
         echo "                   (option \"${PAUSE_OPT_CLEAN}\") or stop the current run (option"
         echo "                   \"${PAUSE_OPT_STOP}\") while remaining runs continue as normal."
         echo "                   Alternatively, you can also pause or stop this and all subsequent "
         echo "                   runs (option \"${PAUSE_OPT_PAUSEALL}\" and \"${PAUSE_OPT_STOPALL}\","
         echo "                   respectively)."
         menu_select -m "How would you like to proceed?" "${PAUSE_OPT_PAUSE}" "${PAUSE_OPT_RESUME}" \
                     "${PAUSE_OPT_CLEAN}" "${PAUSE_OPT_STOP}" "${PAUSE_OPT_PAUSEALL}" \
                     "${PAUSE_OPT_STOPALL}"
         CHOICE=${?}
         case ${CHOICE} in
            0 | 4) # Continue to pause the run and go to the next one. Also, pausing all runs, if
                   # selected.
               echo "radiotrans_run.sh: Run ${LABEL} will remain paused."
               if [ ${CHOICE} -eq 4 ]; then
                  echo "radiotrans_run.sh: Subsequent runs have also been paused."
                  break
               fi
               continue
               ;;
            1) # Resume the run.
               echo "radiotrans_run.sh: Run ${LABEL} resuming."
               RESUMING_FROM_PAUSE=1
               rm -f "${PAUSE_FILE}"
               delete_files "${WORK_DIR}/*.dtmp"
               transfer_files --dest-dir "${WORK_DIR}" --src-dir "${RESULTS_DIR}" \
                               "*.npy" "*.png" "*.comm" "*.txt"
               if [ ${?} -ne 0 ]; then
                  echo "radiotrans_run.sh: Could not resume run ${LABEL}.  It may be necessary"
                  echo "                   to delete the run and restart it from scratch."
                  continue
               fi
               ;;
            2) # Restart the run as a clean run.
               echo "radiotrans_run.sh: Restarting run ${LABEL} as a clean run."
               rm -f "${PAUSE_FILE}"
               CLEAN_RUN=1
               ;;
            3 | 5) # Unpause and stop the current run.  Also, stop all subsequent runs, if selected.
               echo "radiotrans_run.sh: Stopping run ${LABEL}."
               rm -f "${PAUSE_FILE}"
               if [ ${CHOICE} -eq 5 ]; then
                  echo "radiotrans_run.sh: Stopping all subsequent runs."
                  break
               fi
               continue
               ;;
            -1 )
               echo "radiotrans_run.sh: Script needs more debugging :("
               exit 1
               ;;
         esac
      fi

      # If this is to be a clean run, then clear the results directory.
      if [ -n "${CLEAN_RUN}" ] && [ ${CLEAN_RUN} -eq 1 ] && [ ${RESUMING_FROM_PAUSE} -eq 0 ]; then
         echo "radiotrans_run.sh: Cleaning results directory."
         rm -rf "${RESULTS_DIR}"
         mkdir -p "${RESULTS_DIR}"
         if [ ! -d "${RESULTS_DIR}" ]; then
            echo "radiotrans_run.sh: Could not recreate results directory ${RESULTS_DIR}"
            RUN_STATUS=1
         fi
      fi
   fi


   # Reload work if requested by user and this is not a clean run.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${RELOAD_WORK} -eq 1 ] && [ -z "${CLEAN_RUN}" ] \
      && [ ${RESUMING_FROM_PAUSE} -eq 0 ]; then
      echo "radiotrans_run.sh: Reloading files for run ${LABEL} into working directory."
      # Build the command-line to perform the file transfer to the working directory from results
      # directory.
      CMD_TRANSFER="${INSTALL_DIR}/radiotransfer.sh"
      CMD_TRANSFER_OPTS=(--install-dir "${INSTALL_DIR}" \
            --work-dir "${WORK_DIR}" --label "${LABEL}" --results-dir "${RESULTS_DIR}"  \
            --reload-work ${FORCE_TRANSFER_OPT} ${SUPERCLUSTER_OPT})
      # Perform transfer of file to working directory from results directory.
      ${CMD_TRANSFER} ${CMD_TRANSFER_OPTS[*]}
      RUN_STATUS=${?}
      if [ ${RUN_STATUS} -ne 0 ]; then
         echo "radiotrans_run.sh: An error occurred reloading files.  Skipping run ${LABEL}"
         echo "                   It may be necessary to delete the run and restart it."
         continue
      fi
   fi

   # Set the default parameters for the current run.
   case ${DEFAULT_PARAMS} in
      1) # Configure parameters for GW170809.
         echo "radiotrans_run.sh: Using GW170809 run parameter set."
         INTEGTIME=100
         DECIMATION=10000
         RFI_STD=5.0
         SNR_CUTOFF=3.0
         SG_PARAMS0=(151 2 151 2)
         SG_PARAMS1=(111 2 151 2)
         LOWER_FFT0=0
         UPPER_FFT0=4095
         LOWER_FFT1=0
         UPPER_FFT1=4095
         BP_WINDOW=10
         BL_WINDOW=50
         SNR_THRESHOLD=5.0
         DM_SEARCH0=(30.0 5000.0 1.0)
         DM_SEARCH1=(30.0 5000.0 1.0)
         MAX_PULSE_WIDTH=2.0
         ;;
      2) # Configure parameters for Cleague.
         echo "radiotrans_run.sh: Using CLEAGUE run parameter set."
         INTEGTIME=2089.80
         DECIMATION=4000
         RFI_STD=5.0
         SNR_CUTOFF=3.0
         SG_PARAMS0=(151 2 151 2)
         SG_PARAMS1=(111 2 151 2)
         LOWER_FFT0=0
         UPPER_FFT0=4095
         LOWER_FFT1=0
         UPPER_FFT1=4095
         BP_WINDOW=11
         BL_WINDOW=51
         SNR_THRESHOLD=5.0
         DM_SEARCH0=(30.0 2000.0 1.0)
         DM_SEARCH1=(30.0 2000.0 1.0)
         MAX_PULSE_WIDTH=2.0
         ;;
      3) # Configure parameters for DEBUGGING.
         echo "radiotrans_run.sh: Using DEBUG run parameter set."
         INTEGTIME=500.0
         DECIMATION=4000
         RFI_STD=5.0
         SNR_CUTOFF=3.0
         SG_PARAMS0=(151 2 151 2)
         SG_PARAMS1=(111 2 151 2)
         ENABLE_HANN_OPT=
         LOWER_FFT0=0
         UPPER_FFT0=4095
         LOWER_FFT1=0
         UPPER_FFT1=4095
         BP_WINDOW=10
         BL_WINDOW=50
         SNR_THRESHOLD=5.0
         DM_SEARCH0=(30.0 2000.0 1.0)
         DM_SEARCH1=(30.0 2000.0 1.0)
         MAX_PULSE_WIDTH=2.0
         ;;
      *) # Configure basic, default parameters.
         INTEGTIME=125
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
         DM_SEARCH0=(30.0 3000.0 1.0)
         DM_SEARCH1=(30.0 3000.0 1.0)
         MAX_PULSE_WIDTH=2.0
         ;;
   esac

   # Import the parameters file, if one given.  This will override some or all of the default parameters
   # for the current run.
   if [ -n "${PARAMS_FILE}" ]; then
      # CCY - This works, simply, but is very unsafe.  I need to fix parse_config(), which is much
      # safer.
      source "${PARAMS_FILE}"
      if [ ${?} -eq 0 ]; then
         echo "radiotrans_run.sh: Run ${LABEL} parameters imported from ${PARAMS_FILE}"
         echo "                   (overrides pre-made values)."
      else
         echo "radiotrans_run.sh (WARNING): An error occurred importing parameters file.  Some run"
         echo "                             parameters may not be set to desired values."
         echo
         menu_select -m "How do you want to proceed?" "${PAUSE_OPT_CONTINUE}" "${PAUSE_OPT_STOP}" \
                     "${PAUSE_OPT_STOPALL}"
         CHOICE=${?}
         case ${CHOICE} in
            0) # Continue current run.
               echo "radiotrans_run.sh: Continuing with run ${LABEL}."
               ;;
            1) # Stop the current run.
               echo "radiotrans_run.sh: Stopping run ${LABEL}"
               continue
               ;;
            2) # Stop all runs.
               echo "radiotrans_run.sh: Stopping run ${LABEL}"
               echo "radiotrans_run.sh: Stopping all runs."
               break
               ;;
         esac
      fi
   fi
   echo "radiotrans_run.sh: Current run parameters."
   echo "     INTEGTIME = ${INTEGTIME}"
   echo "     ENABLE_HANN_OPT = ${ENABLE_HANN_OPT}"
   echo "     TIME_AVERAGE_TOGGLE = ${NO_TIME_AVG_OPT}"
   echo "     DECIMATION = ${DECIMATION}"
   echo "     RFI_STD = ${RFI_STD}"
   echo "     SNR_CUTOFF = ${SNR_CUTOFF}"
   echo "     SG_PARAMS0 = ${SG_PARAMS0[*]}"
   echo "     SG_PARAMS1 = ${SG_PARAMS1[*]}"
   echo "     LOWER_FFT0 = ${LOWER_FFT0}"
   echo "     UPPER_FFT0 = ${UPPER_FFT0}"
   echo "     LOWER_FFT1 = ${LOWER_FFT1}"
   echo "     UPPER_FFT1 = ${UPPER_FFT1}"
   echo "     BP_WINDOW = ${BP_WINDOW}"
   echo "     BL_WINDOW = ${BL_WINDOW}"
   echo "     SNR_THRESHOLD = ${SNR_THRESHOLD}"
   echo "     DM_SEARCH0 = ${DM_SEARCH0[*]}"
   echo "     DM_SEARCH1 = ${DM_SEARCH1[*]}"
   echo "     MAX_PULSE_WDITH = ${MAX_PULSE_WIDTH}"
   echo "     INJ_NUM = ${INJ_NUM}"
   echo "     INJ_POWER = ${INJ_POWER}"
   echo "     INJ_SPECTINDEX = ${INJ_SPECTINDEX}"
   echo "     INJ_TIMES = ${INJ_TIMES[*]}"
   echo "     INJ_DMS = ${INJ_DMS[*]}"
   echo "     INJ_REGULAR_TIMES_OPT = ${INJ_REGULAR_TIMES_OPT}"
   echo "     INJ_REGULAR_DMS_OPT = ${INJ_REGULAR_DMS_OPT}"
   echo "     INJ_ONLY_OPT = ${INJ_ONLY_OPT}"
   echo

   # Stage to reduce radio data.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${SKIP_REDUCE} -eq 0 ]; then
      if [ ${SKIP_REDUCE} -eq 0 ]; then
         # Build the command-line to perform data reduction.
         CMD_REDUCE="${INSTALL_DIR}/radioreduce.sh"
         CMD_REDUCE_OPTS=(--install-dir "${INSTALL_DIR}" --integrate-time ${INTEGTIME} \
               --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} ${ENABLE_HANN_OPT} \
               --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" ${NO_TIME_AVG_OPT} \
               --decimation ${DECIMATION} --rfi-std-cutoff ${RFI_STD} --snr-cutoff ${SNR_CUTOFF} \
               --data-utilization ${DATA_UTILIZE} ${SUPERCLUSTER_OPT} ${NO_REDUCE_INTERACT_OPT} \
               --savitzky-golay0 "${SG_PARAMS0[*]}" --savitzky-golay1 "${SG_PARAMS1[*]}" \
               --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${DELWATERFALLS_OPT})
         # Add options for injections.
         INJ_VARS=(INJ_NUM INJ_SPECTINDEX INJ_POWER INJ_TIMES INJ_DMS)
         INJ_OPTS=("--num-injections" "--inject-spectral-index" "--inject-power" \
                   "--injection-time-span" "--injection-dm-span")
         for INDEX in ${!INJ_VARS[@]}
         do
            VAR_VALUE="${INJ_VARS[${INDEX}]}[*]"
            if [ -n "${!VAR_VALUE}" ]; then
               CMD_REDUCE_OPTS=(${INJ_OPTS[${INDEX}]} ${!VAR_VALUE} ${CMD_REDUCE_OPTS[*]})
            fi
         done
         CMD_REDUCE_OPTS=(${INJ_REGULAR_TIMES_OPT} ${INJ_REGULAR_DMS_OPT} ${INJ_ONLY_OPT} \
                           ${CMD_REDUCE_OPTS[*]})

         # Perform the data reduction phase.
         ${CMD_REDUCE} ${CMD_REDUCE_OPTS[*]} "${DATA_PATH}"
         RUN_STATUS=${?}
      else
         echo "radiotrans_run.sh: Skipping data reduction per user request."
         echo
      fi
   fi

   # Stage to perform RFI-bandpass filtration.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${SKIP_RFIBP} -eq 0 ]; then
      # Handle pause point before RFI-bandpass.
      if [ -n "${PLAY_NICE_OPT}" ] && [ ! -f "${PAUSE_FILE}" ]; then
         echo "radiotrans_run.sh: Run \"${LABEL}\" has hit a convenient pause point."
         echo "                   The run can be saved at this point and resumed later (option "
         echo "                   \"${PAUSE_OPT_PAUSE}\"), continued (option \"${PAUSE_OPT_CONTINUE}\"),"
         echo "                   or stopped (option \"${PAUSE_OPT_STOP}\"). "
         echo
         echo "                   Alternatively, this and subsequent runs can be paused (option "
         echo "                   \"${PAUSE_OPT_PAUSEALL}\") or stopped (option \"${PAUSE_OPT_STOPALL}\")."
         menu_select -m "How would you like the run to proceed?" "${PAUSE_OPT_PAUSE}" \
                     "${PAUSE_OPT_CONTINUE}" "${PAUSE_OPT_STOP}" "${PAUSE_OPT_PAUSEALL}" \
                     "${PAUSE_OPT_STOPALL}"
         CHOICE=${?}
         case ${CHOICE} in
            0 | 3) # Pause the current run. Also pause all subsequent runs, if selected.
               echo "radiotrans_run.sh: Pausing run \"${LABEL}\"."
               # Delete any temporary files and then transfer results so far to results directory.. 
               echo "                   Removing temporary files from working directory..."
               delete_files "${WORK_DIR}/*.dtmp"
               echo "                   Saving current results to results directory..."
               transfer_files --src-dir "${WORK_DIR}" --dest-dir "${RESULTS_DIR}" \
                               "*.npy" "*.png" "*.comm" "*.txt"
               # Mark the run as paused; then proceed to the next run.
               touch "${PAUSE_FILE}"
               echo "radiotrans_run.sh: Run \"${LABEL}\" paused."
               if [ ${CHOICE} -eq 3 ]; then
                  # Stop all subsequent runs.
                  echo "radiotrans_run.sh: All subsequent runs paused."
                  break
               fi
               RUNS_REMAIN=`expr ${#LABELS[@]} - ${RUN_INDEX} - 1`
               if [ ${RUNS_REMAIN} -gt 1 ] && [ -z "${CONTINUE_ALL}" ]; then
                  if [ ${RUNS_REMAIN} -gt 1 ]; then
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more runs remain to do."
                  else
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more run remains to do."
                  fi
                  while [ 1 ]
                  do
                     menu_select -m "How would you like to proceed?" "${PAUSE_OPT_CONTINUE}" \
                                    "${PAUSE_OPT_CONTINUEALL}" "${PAUSE_OPT_STOPALL}"
                     CHOICE=${?}
                     case ${CHOICE} in
                        0) # Continue to next run.
                           echo "radiotrans_run.sh: Continuing to next run."
                           break
                           ;;
                        1) # Continue with all subsequent runs.
                           echo "radiotrans_run.sh: All runs will continue without asking this question "
                           echo "                   again."
                           menu_select -m "Are you sure?" "No" "Yes"
                           CHOICE=${?}
                           if [ ${CHOICE} -eq 1 ]; then
                              CONTINUE_ALL="DO IT!"
                              break
                           fi
                           ;;
                        2) # Stop everything here.
                           echo "radiotrans_run.sh: Stopping here.  Execute radiotrans_run.sh again, with "
                           echo "                   appropriate parameters to resume with remaining runs."
                           ALL_STATUS=1
                           STOP_ALL="DO IT!"
                           break
                           ;;
                     esac
                  done
                  if [ -n "${STOP_ALL}" ]; then
                     break
                  fi
               fi
               continue
               ;;
            2 | 4) # Stop the current run without saving. Also, stop all subsequent runs, if selected.
               echo "radiotrans_run.sh: Stopping run ${LABEL}."
               rm -f "${PAUSE_FILE}"
               if [ ${CHOICE} -eq 4]; then
                  # Stop all subsequent runs.
                  echo "radiotrans_run.sh: Stopping all subsequent runs."
                  break
               fi
               RUNS_REMAIN=`expr ${#LABELS[@]} - ${RUN_INDEX} - 1`
               if [ ${RUNS_REMAIN} -gt 1 ] && [ -z "${CONTINUE_ALL}" ]; then
                  if [ ${RUNS_REMAIN} -gt 1 ]; then
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more runs remain to do."
                  else
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more run remains to do."
                  fi
                  while [ 1 ]
                  do
                     menu_select -m "How would you like to proceed?" "${PAUSE_OPT_CONTINUE}" \
                                    "${PAUSE_OPT_CONTINUEALL}" "${PAUSE_OPT_STOPALL}"
                     CHOICE=${?}
                     case ${CHOICE} in
                        0) # Continue to next run.
                           echo "radiotrans_run.sh: Continuing to next run."
                           break
                           ;;
                        1) # Continue with all subsequent runs.
                           echo "radiotrans_run.sh: All runs will continue without asking this question "
                           echo "                   again."
                           menu_select -m "Are you sure?" "No" "Yes"
                           CHOICE=${?}
                           if [ ${CHOICE} -eq 1 ]; then
                              CONTINUE_ALL="DO IT!"
                              break
                           fi
                           ;;
                        2) # Stop everything here.
                           echo "radiotrans_run.sh: Stopping here.  Execute radiotrans_run.sh again, with "
                           echo "                   appropriate parameters to resume with remaining runs."
                           ALL_STATUS=1
                           STOP_ALL="DO IT!"
                           break
                           ;;
                     esac
                  done
                  if [ -n "${STOP_ALL}" ]; then
                     break
                  fi
               fi
               continue
               ;;
            1) # Continue with the current run.
               echo "radiotrans_run.sh: Continuing with run ${LABEL}."
               ;;
            *) # Something went wrong.  Needs more debugging.
               echo "radiotrans_run.sh: Script needs more debugging :("
               exit 1
               ;;
         esac
      fi

      echo
      echo "radiofilter.sh: ALERT!=> User is advised to examine bandpass, baseline, and spectrogram "
      echo "                plots to determine appropriate FFT index bounds and smoothing window "
      echo "                parameters before performing RFI-bandpass filtration."
      echo
      sleep 2

      echo "radiotrans_run.sh: Current RFI-bandpass parameters =>"
      echo "   Lower FFT Index Tuning 0 = ${LOWER_FFT0}"
      echo "   Upper FFT Index Tuning 0 = ${UPPER_FFT0}"
      echo "   Lower FFT Index Tuning 1 = ${LOWER_FFT1}"
      echo "   Upper FFT Index Tuning 1 = ${UPPER_FFT1}"
      echo "   Bandpass smoothing window = ${BP_WINDOW}"
      echo "   Baseline smoothing window = ${BL_WINDOW}"

      while [ 1 ] && [ -z "${NO_RFIBP_INTERACT_OPT}" ]
      do
         menu_select -m "radiofilter.sh: Proceed with the current parameters?" \
                 "Proceed" "Change" "Quit" 
         CHOICE=${?}
         if [ ${CHOICE} -eq 0 ]; then
            # Proceed to the RFI-bandpass filtration.
            echo "radiofilter.sh: Proceeding to RFI-bandpass filtration."
            break
         elif [ ${CHOICE} -eq 2 ]; then
            # Quit from RFI-bandpass filtration.
            echo "radiotrans_run.sh: Quitting from RFI-bandpass filtration."
            RUN_STATUS=1
            break
         elif [ ${CHOICE} -eq 1 ]; then
            while [ 1 ]
            do
               # Get new parameters for RFI-bandpass filtration from user.
               menu_select -m "Select parameter to change:" "${LFFT0_STR}" "${UFFT0_STR}" \
                           "${LFFT1_STR}" "${UFFT1_STR}" "${BPW_STR}" "${BLW_STR}" "Done"
               CHOICE=${?}
               case ${CHOICE} in
                  0 | 1 | 2 | 3 | 4 | 5) # Change a parameter.
                     while [ 1 ] 
                     do
                        echo "Enter integer value for parameter: "
                        read USER_VAL
                        if [[ "${USER_VAL}" =~ ${INTEGER_NUM} ]]; then
                           case ${CHOICE} in
                              0 | 1 | 2 | 3 ) # Change FFT index bounds.
                                 if [ ${USER_VAL} -gt -1 ] && [ ${USER_VAL} -lt 4095 ]; then
                                    case ${CHOICE} in
                                       0)
                                          LOWER_FFT0=${USER_VAL}
                                          ;;
                                       1)
                                          UPPER_FFT0=${USER_VAL}
                                          ;;
                                       2)
                                          LOWER_FFT1=${USER_VAL}
                                          ;;
                                       3)
                                          UPPER_FFT1=${USER_VAL}
                                          ;;
                                    esac
                                    break
                                 else
                                    echo "Entered value must be an integer from 0 to 4094"
                                 fi
                                 ;;
                              4 | 5 ) # Change smoothing parameters.
                                 if [ ${USER_VAL} -gt 0 ]; then
                                    case ${CHOICE} in
                                       4)
                                          BP_WINDOW=${USER_VAL}
                                          ;;
                                       5)
                                          BL_WINDOW=${USER_VAL}
                                          ;;
                                    esac
                                    break
                                 else
                                    echo "Entered value must be an integer greater than 0"
                                 fi
                                 ;;
                           esac
                        else
                           echo "Entered value must be an integer. "
                        fi
                     done
                     continue
                     ;;
                  6 ) # Done changing parameters.
                     break
                     ;;
                  * ) # Invalid choice.
                     continue
                     ;;
               esac
            done
         else
            continue
         fi

         echo "   Lower FFT Index Tuning 0 = ${LOWER_FFT0}"
         echo "   Upper FFT Index Tuning 0 = ${UPPER_FFT0}"
         echo "   Lower FFT Index Tuning 1 = ${LOWER_FFT1}"
         echo "   Upper FFT Index Tuning 1 = ${UPPER_FFT1}"
         echo "   Bandpass smoothing window = ${BP_WINDOW}"
         echo "   Baseline smoothing window = ${BL_WINDOW}"
      done # endwhile

      # If we're done interacting and not selected to quit, then do the RFI-bandpass filtration.
      if [ ${RUN_STATUS} -eq 0 ]; then
         # Build the command-line to perform the RFI-bandpass filtration.
         CMD_FILTER="${INSTALL_DIR}/radiofilter.sh"
         CMD_FILTER_OPTS=(--install-dir "${INSTALL_DIR}" ${DISABLE_RFI_OPT} \
               --nprocs ${NUM_PROCS} --memory-limit ${MEM_LIMIT} --no-interact \
               --work-dir "${WORK_DIR}" --config-file "${COMMCONFIG_FILE}" \
               --label "${LABEL}" --results-dir "${RESULTS_DIR}" ${SUPERCLUSTER_OPT} \
               --lower-fft-index0 ${LOWER_FFT0} --upper-fft-index0 ${UPPER_FFT0} \
               --lower-fft-index1 ${LOWER_FFT1} --upper-fft-index1 ${UPPER_FFT1} \
               --bandpass-window ${BP_WINDOW} --baseline-window ${BL_WINDOW} \
               --decimation ${DECIMATION} --rfi-std-cutoff ${RFI_STD} --snr-cutoff ${SNR_CUTOFF} \
               --savitzky-golay0 "${SG_PARAMS0[*]}" --savitzky-golay1 "${SG_PARAMS1[*]}")
         # Perform the RFI-bandpass filtration.
         ${CMD_FILTER} ${CMD_FILTER_OPTS[*]}
         RUN_STATUS=${?}
      fi 
   else
      if [ ${RUN_STATUS} -eq 0 ] && [ ${SKIP_RFIBP} -eq 1 ]; then
         echo "radiotrans_run.sh: Skipping RFI-bandpass filtration per user request."
         echo
      fi
   fi

   # Stage to perform de-dispered search.
   if [ ${RUN_STATUS} -eq 0 ] && [ ${DO_DDISP_SEARCH} -eq 1 ]; then
      # Handle pause point before de-dispersed search.
      if [ -n "${PLAY_NICE_OPT}" ] && [ ! -f "${PAUSE_FILE}" ]; then
         echo "radiotrans_run.sh: Run \"${LABEL}\" has hit a convenient pause point."
         echo "                   The run can be saved at this point and resumed later (option "
         echo "                   \"${PAUSE_OPT_PAUSE}\"), continued (option \"${PAUSE_OPT_CONTINUE}\"),"
         echo "                   or stopped (option \"${PAUSE_OPT_STOP}\"). "
         echo
         echo "                   Alternatively, this and subsequent runs can be paused (option "
         echo "                   \"${PAUSE_OPT_PAUSEALL}\") or stopped (option \"${PAUSE_OPT_STOPALL}\")."
         menu_select -m "How would you like the run to proceed?" "${PAUSE_OPT_PAUSE}" \
                     "${PAUSE_OPT_CONTINUE}" "${PAUSE_OPT_STOP}" "${PAUSE_OPT_PAUSEALL}" \
                     "${PAUSE_OPT_STOPALL}"
         CHOICE=${?}
         case ${CHOICE} in
            0 | 3) # Pause the current run. Also pause all subsequent runs, if selected.
               echo "radiotrans_run.sh: Pausing run \"${LABEL}\"."
               # Delete any temporary files and then transfer results so far to results directory.. 
               echo "                   Removing temporary files from working directory..."
               delete_files "${WORK_DIR}/*.dtmp"
               echo "                   Saving current results to results directory..."
               transfer_files --src-dir "${WORK_DIR}" --dest-dir "${RESULTS_DIR}" \
                               "*.npy" "*.png" "*.comm" "*.txt"
               # Mark the run as paused; then proceed to the next run.
               touch "${PAUSE_FILE}"
               echo "radiotrans_run.sh: Run \"${LABEL}\" paused."
               if [ ${CHOICE} -eq 3 ]; then
                  # Stop all subsequent runs.
                  echo "radiotrans_run.sh: All subsequent runs paused."
                  break
               fi
               RUNS_REMAIN=`expr ${#LABELS[@]} - ${RUN_INDEX} - 1`
               if [ ${RUNS_REMAIN} -gt 1 ] && [ -z "${CONTINUE_ALL}" ]; then
                  if [ ${RUNS_REMAIN} -gt 1 ]; then
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more runs remain to do."
                  else
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more run remains to do."
                  fi
                  while [ 1 ]
                  do
                     menu_select -m "How would you like to proceed?" "${PAUSE_OPT_CONTINUE}" \
                                    "${PAUSE_OPT_CONTINUEALL}" "${PAUSE_OPT_STOPALL}"
                     CHOICE=${?}
                     case ${CHOICE} in
                        0) # Continue to next run.
                           echo "radiotrans_run.sh: Continuing to next run."
                           break
                           ;;
                        1) # Continue with all subsequent runs.
                           echo "radiotrans_run.sh: All runs will continue without asking this question "
                           echo "                   again."
                           menu_select -m "Are you sure?" "No" "Yes"
                           CHOICE=${?}
                           if [ ${CHOICE} -eq 1 ]; then
                              CONTINUE_ALL="DO IT!"
                              break
                           fi
                           ;;
                        2) # Stop everything here.
                           echo "radiotrans_run.sh: Stopping here.  Execute radiotrans_run.sh again, with "
                           echo "                   appropriate parameters to resume with remaining runs."
                           ALL_STATUS=1
                           STOP_ALL="DO IT!"
                           break
                           ;;
                     esac
                  done
                  if [ -n "${STOP_ALL}" ]; then
                     break
                  fi
               fi
               continue
               ;;
            2 | 4) # Stop the current run without saving. Also, stop all subsequent runs, if selected.
               echo "radiotrans_run.sh: Stopping run ${LABEL}."
               rm -f "${PAUSE_FILE}"
               if [ ${CHOICE} -eq 4]; then
                  echo "radiotrans_run.sh: Stopping all subsequent runs."
                  break
               fi
               RUNS_REMAIN=`expr ${#LABELS[@]} - ${RUN_INDEX} - 1`
               if [ ${RUNS_REMAIN} -gt 1 ] && [ -z "${CONTINUE_ALL}" ]; then
                  if [ ${RUNS_REMAIN} -gt 1 ]; then
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more runs remain to do."
                  else
                     echo "radiotrans_run.sh: ${RUNS_REMAIN} more run remains to do."
                  fi
                  while [ 1 ]
                  do
                     menu_select -m "How would you like to proceed?" "${PAUSE_OPT_CONTINUE}" \
                                    "${PAUSE_OPT_CONTINUEALL}" "${PAUSE_OPT_STOPALL}"
                     CHOICE=${?}
                     case ${CHOICE} in
                        0) # Continue to next run.
                           echo "radiotrans_run.sh: Continuing to next run."
                           break
                           ;;
                        1) # Continue with all subsequent runs.
                           echo "radiotrans_run.sh: All runs will continue without asking this question "
                           echo "                   again."
                           menu_select -m "Are you sure?" "No" "Yes"
                           CHOICE=${?}
                           if [ ${CHOICE} -eq 1 ]; then
                              CONTINUE_ALL="DO IT!"
                              break
                           fi
                           ;;
                        2) # Stop everything here.
                           echo "radiotrans_run.sh: Stopping here.  Execute radiotrans_run.sh again, with "
                           echo "                   appropriate parameters to resume with remaining runs."
                           ALL_STATUS=1
                           STOP_ALL="DO IT!"
                           break
                           ;;
                     esac
                  done
                  if [ -n "${STOP_ALL}" ]; then
                     break
                  fi
               fi
               continue
               ;;
            1) # Continue with the current run.
               echo "radiotrans_run.sh: Continuing with run ${LABEL}."
               ;;
            *) # Something went wrong.  Needs more debugging.
               echo "radiotrans_run.sh: Script needs more debugging :("
               exit 1
               ;;
         esac
      fi
      CMBPREFIX="spectrogram"
      if [ -n "${LABEL}" ]; then
         CMBPREFIX="${CMBPREFIX}_${LABEL}"
      fi
      # Check for T0 RFI-bandpass filtered spectrogram.
      if [ ! -f "${WORK_DIR}/rfibp-${CMBPREFIX}-T0.npy" ]; then
         echo "radiotrans_run.sh: Missing T0 RFI-bandpass filtered spectrogram."
         echo "                 Copying T0 unfiltered spectrogram as RFI-bandpass filtered."
         echo
         cp "${WORK_DIR}/${CMBPREFIX}-T0.npy" "${WORK_DIR}/rfibp-${CMBPREFIX}-T0.npy"
      fi

      # Check for T1 RFI-bandpass filtered spectrogram.
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
            --dm-search0 "${DM_SEARCH0[*]}" --dm-search1 "${DM_SEARCH1[*]}" \
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
            --work-dir "${WORK_DIR}" --label "${LABEL}" --results-dir "${RESULTS_DIR}" \
            ${SKIP_TRANSFER_OPT} ${SKIP_TAR_OPT} ${FORCE_TRANSFER_OPT} )
      # Perform transfer of results to results directory and build tar of results.
      ${CMD_TRANSFER} ${CMD_TRANSFER_OPTS[*]}
      RUN_STATUS=${?}
   fi

   # Report workflow execution status to user.
   if [ ${RUN_STATUS} -eq 0 ]; then
      echo "radiotrans_run.sh: All workflow phases executed successfully!"
      echo
   else
      echo "radiotrans_run.sh: Some phases of the workflow failed or were not executed."
      echo "                   Additional debug/investigation may be needed :("
      echo "   LABEL = ${LABEL}"
      echo "   DATA_FILE = ${DATA_PATH}"
      echo "   WORK_DIR = ${WORK_DIR}"
      echo "   RESULTS_DIR = ${RESULTS_DIR}"
      echo "   PARAMS_FILE = ${PARAMS_FILE}"
      echo
      ALL_STATUS=1
   fi

   if [ -n "${PLAY_NICE_OPT}" ]; then
      RUNS_REMAIN=`expr ${#LABELS[@]} - ${RUN_INDEX} - 1`
      if [ ${RUNS_REMAIN} -gt 0 ] && [ -z "${CONTINUE_ALL}" ]; then
         if [ ${RUNS_REMAIN} -gt 1 ]; then
            echo "radiotrans_run.sh: ${RUNS_REMAIN} more runs remain to do."
         else
            echo "radiotrans_run.sh: ${RUNS_REMAIN} more run remains to do."
         fi
         while [ 1 ]
         do
            menu_select -m "How would you like to proceed?" "${PAUSE_OPT_CONTINUE}" \
                           "${PAUSE_OPT_CONTINUEALL}" "${PAUSE_OPT_STOPALL}"
            CHOICE=${?}
            case ${CHOICE} in
               0) # Continue to next run.
                  echo "radiotrans_run.sh: Continuing to next run."
                  break
                  ;;
               1) # Continue with all subsequent runs.
                  echo "radiotrans_run.sh: All runs will continue without asking this question again."
                  menu_select -m "Are you sure?" "No" "Yes"
                  CHOICE=${?}
                  if [ ${CHOICE} -eq 1 ]; then
                     CONTINUE_ALL="DO IT!"
                     break
                  fi
                  ;;
               2) # Stop everything here.
                  echo "radiotrans_run.sh: Stopping here.  Execute radiotrans_run.sh again, with "
                  echo "                   appropriate parameters to resume with remaining runs."
                  ALL_STATUS=1
                  STOP_ALL="DO IT!"
                  break
                  ;;
            esac
         done
         if [ -n "${STOP_ALL}" ]; then
            break
         fi
      fi
   fi
done

if [ ${ALL_STATUS} -eq 0 ]; then
   echo "radiotrans_run.sh: All runs of the workflow executed successfully!"
   echo
else
   echo "radiotrans_run.sh: Some runs of the workflow failed or were not executed."
   echo
fi
exit ${ALL_STATUS}
