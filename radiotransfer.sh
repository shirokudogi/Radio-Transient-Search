#!/bin/bash
#
# Created by:     Cregg C. Yancey
#
# PURPOSE: Transfer final results of data reduction and RFI-bandpass filtration to the results
#           directory and create a tar ball of the results directory for transfer via sftp to remote
#           systems.

# Make sure extended regular expressions are supported.
shopt -s extglob


source "OPT-INSTALL_DIR/text_patterns.sh"
#source "${HOME}/dev/radiotrans/text_patterns.sh"   # Use only when debugging.

USAGE='
radiotransfer.sh

   radiotransfer.sh [-t | --integrate-time <time>] [-n | --nprocs <num>] [-i | --install-dir <path>]
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



# ==== MAIN WORKFLOW FOR RADIOTRANSFER.SH ===
#
#
# Set the install path for the radio transient search workflow scripts.  
# NOTE: the string 'OPT-INSTALL_DIR' is replaced by the git-export.sh script with the path to directory 
# in which the radio transient scripts have been installed.  However, the user is free to manually change
# this.
INSTALL_DIR=
WORK_DIR=            # Working directory.
RESULTS_DIR=         # Results directory.
LABEL=               # User label attached to output files from data reduction.
SUPERCLUSTER=0       # Flag denoting whether we should initialize for being on a supercluster.
COMMCONFIG_FILE=     # Name of the common configuration file.
SKIP_TAR=0           # Flag denoting whether to skip making tar file of results.
SKIP_TRANSFER=0      # Flag denoting to skip the actual transfer.
RELOAD_WORK=0        # Flag denoting to reload results back into the work directory.
FORCE_OPT=



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
         -s | --supercluster) # Specify that we need to initialize for execution on a supercluster.
            SUPERCLUSTER=1
            shift
            ;;
         --skip-tar ) # Specify to skip building tar file of results.
            SKIP_TAR=1
            shift
            ;;
         --skip-transfer ) # Specify to actual transfer of files to results directory
            SKIP_TRANSFER=1
            shift
            ;;
         --reload-work ) # Transfer key results file from the results directory to the work directory.
            RELOAD_WORK=1
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
         -f | --force-repeat) # Force repeat of previously complete stages.
            FORCE_OPT="-f"
            shift
            ;;
         *) # Ignore
            shift 
            ;;
      esac
   done
else
   echo "ERROR: radiotransfer.sh -> Nothing specified to do"
   echo "${USAGE}"
   exit 1
fi

# Check that specified install path exists and that all necessary components are contained.
if [ -z "${INSTALL_DIR}" ]; then
   INSTALL_DIR="OPT-INSTALL_DIR"
fi
if [ -d "${INSTALL_DIR}" ]; then
   package_modules=(resume.sh utils.sh)
   for module in ${package_modules[*]}; do
      MODULE_PATH="${INSTALL_DIR}/${module}"
      if [ ! -f "${MODULE_PATH}" ]; then
         echo "ERROR: radiotransfer.sh -> Missing package module"
         echo "     ${MODULE_PATH}"
         exit 1
      fi
   done
else
   echo "ERROR: radiotransfer.sh -> Install path does not exist"
   echo "     ${INSTALL_DIR}"
   exit 1
fi

# Check that the working directory exists.
if [ -z "${WORK_DIR}" ]; then
   WORK_DIR="."
fi
if [ ! -d "${WORK_DIR}" ]; then
   echo "ERROR: radiotransfer.sh -> working directory does not exist.  User may need to create it."
   echo "     ${WORK_DIR}"
   exit 1
fi

# Check that the results directory exists.
if [ -z "${RESULTS_DIR}" ]; then
   RESULTS_DIR="."
fi
if [ ! -d "${RESULTS_DIR}" ]; then
   echo "ERROR: radiotransfer.sh -> results directory does not exist.  User may need to create it."
   echo "     ${RESULTS_DIR}"
   exit 1
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

LBL_RESULTS="Results_Transfer"
LBL_TAR="TAR_Files"
LBL_DELWORK="DeleteWorkingDir"
LBL_RELOAD="Reload_Work"

if [ ${RELOAD_WORK} -eq 0 ]; then
   # Transfer results files to the results directory, if allowed by the user.
   if [ ${SKIP_TRANSFER} -eq 0 ]; then
      # Move results files if the working directory and results directory are different.
      if [[ "${WORK_DIR}" != "${RESULTS_DIR}" ]]; then
         echo "radiotransfer.sh: Transferring key results files to directory ${RESULTS_DIR}..."
         echo "   ${WORK_DIR} ---> ${RESULTS_DIR}"
         echo
         resumecmd -l ${LBL_RESULTS} ${FORCE_OPT} \
                   transfer_files --src-dir "${WORK_DIR}" --dest-dir "${RESULTS_DIR}" \
                   "*.npy" "*.png" "*.comm" "*.txt"
         report_resumecmd

         # Delete the working directory, since we don't need it now, as long as it is not the current
         # directory.  As a safety, we want to avoid deleting the current directory.
         if [[ "${WORK_DIR}" != "." ]] && [[ ${KEEP_WORK_DIR} -eq 0 ]]; then
            echo "Removing working directory."
            resumecmd -l ${LBL_DELWORK} ${FORCE_OPT} -k ${RESUME_LASTCMD_SUCCESS} \
                      rm -rf "${WORK_DIR}"
            report_resumecmd
         fi
      else
         echo "radiotransfer.sh: Skipping results transfer => working and results directories are the same."
      fi

      # Build tar-file of results for sftp transfer to other systems.
      if [ -n "${LABEL}" -a ${SKIP_TAR} -eq 0 ]; then
         echo "radiotransfer.sh: Building tar file of results."
         pushd "${RESULTS_DIR}" 1>/dev/null
         TAR_FILES=$(ls ./*.npy ./*.png ./*.comm ./*.txt 2>/dev/null)
         resumecmd -l ${LBL_TAR} ${FORCE_OPT} \
                   tar -cvzf "${RESULTS_DIR}/${LABEL}.tar.gz" "${TAR_FILES[*]}"
         report_resumecmd
         popd 1>/dev/null
      else
         echo "radiotransfer.sh: Skipping creation of tar file per user request or because no run labeL."
      fi
   else
      echo "radiotransfer.sh: Skipping results transfer per user request"
      # Build tar-file of results for sftp transfer to other systems.
      if [ -n "${LABEL}" -a ${SKIP_TAR} -eq 0 ]; then
         echo "radiotransfer.sh: Building tar file of results."
         pushd "${WORK_DIR}" 1>/dev/null
         TAR_FILES=$(ls ./*.npy ./*.png ./*.comm ./*.txt 2>/dev/null)
         if [ -n "${TAR_FILES[*]}" ]; then
            resumecmd -l ${LBL_TAR} ${FORCE_OPT} \
                      tar -cvzf "${WORK_DIR}/${LABEL}.tar.gz" "${TAR_FILES[*]}"
            report_resumecmd
         fi
         popd 1>/dev/null
      else
         echo "radiotransfer.sh: Skipping creation of tar file per user request or because no run label."
      fi

   fi
else
   if [[ "${WORK_DIR}" != "${RESULTS_DIR}" ]]; then
      echo "radiotransfer.sh: Reloading from key files from results directory to working directory..."
      echo "   ${RESULTS_DIR} ---> ${WORK_DIR}"
      echo
      resumecmd -l ${LBL_RELOAD} ${FORCE_OPT} \
         transfer_files --src-dir "${RESULTS_DIR}" --dest-dir "${WORK_DIR}" \
         "*.npy" "*.png" "*.comm" "*.txt"
      report_resumecmd
   else
      echo "radiotransfer.sh: Skipping reload => results and working directories are the same."
   fi
fi

# Determine exit status
if [ -z "${RESUME_LASTCMD_SUCCESS}" ] || [ ${RESUME_LASTCMD_SUCCESS} -eq 1 ]; then
   echo "radiotransfer.sh: File transfer workflow completed successfully!"
   echo "radiotransfer.sh: Workflow exiting with status 0."
   echo
   exit 0
else
   echo "radiotransfer.sh: File transfer workflow ended, but not all components were executed."
   echo "radiotransfer.sh: Workflow exiting with status 1"
   echo
   exit 1
fi
