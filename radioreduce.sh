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
DATA_UTILIZE=        # Fraction of the spectrogram lines to output from the raw data.
                     
NUM_PROCS=           # Number of concurrent processes to use under MPI
SUPERCLUSTER=0       # Flag denoting whether we should initialize for being on a supercluster.

COMMCONFIG_FILE=     # Name of the common configuration file.

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
         --enable-hann) # Enable Hann windowing on the raw DFTs during reduction.
            ENABLE_HANN="--enable-hann"
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
if [ ${SUPERCLUSTER} -eq 1 ]; then
   module reset
   module load mkl python openmpi
fi



# = RADIO TRANSIENT SEARCH DATA REDUCTION PHASE WORKFLOW =
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


# Generate the waterfall tiles for the reduced-data spectrogram
echo "radioreduce.sh: Generating waterfall tiles for spectrogram from ${DATA_PATH}..."
resumecmd -l ${LBL_WATERFALL} \
   mpirun -np ${NUM_PROCS} python ${INSTALL_DIR}/waterfall.py \
   --integrate-time ${INTEGTIME} --work-dir "${WORK_DIR}" \
   ${ENABLE_HANN} ${LABEL_OPT} --data-utilization ${DATA_UTILIZE} \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --memory-limit ${MEM_LIMIT} "${DATA_PATH}"
report_resumecmd


# Create the combined and coarse combined waterfalls for both tuning 0 and tuning 1.
echo "radioreduce.sh: Combining waterfall sample files into coarse spectrogram files..."
CMBPREFIX="spectrogram"
if [ -n "${LABEL}" ]; then
   CMBPREFIX="${CMBPREFIX}_${LABEL}"
fi
echo "radioreduce.sh: Combining tuning 0 waterfall files into spectrogram..."
resumecmd -l ${LBL_COMBINE0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/waterfallcombine.py \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/${CMBPREFIX}-T0" \
   --decimation ${DECIMATION} \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" "${WORK_DIR}/waterfall*T0.npy"
report_resumecmd
echo "radioreduce.sh: Combining tuning 1 waterfall files into spectrogram..."
resumecmd -l ${LBL_COMBINE1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/waterfallcombine.py \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/${CMBPREFIX}-T1" \
   --decimation ${DECIMATION} \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" "${WORK_DIR}/waterfall*T1.npy"
report_resumecmd


# Create bandpass and baseline images of the coarse combined waterfalls for tunings 0 and 1.
echo "radioreduce.sh: Generating bandpass images of coarse combined waterfall for tuning 0..."
resumecmd -l ${LBL_BANDPASSIMG0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/bandpass-${CMBPREFIX}-T0.png" \
   --label "${LABEL}_Low" "${WORK_DIR}/coarse-${CMBPREFIX}-T0.npy"
report_resumecmd
resumecmd -l ${LBL_SGBANDPASSIMG0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --savitzky-golay "${SG_PARAMS0[0]},${SG_PARAMS0[1]}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/SGbandpass-${CMBPREFIX}-T0.png" \
   --label "SG-${LABEL}_Low" "${WORK_DIR}/coarse-${CMBPREFIX}-T0.npy"
report_resumecmd
echo "radioreduce.sh: Generating baseline images of coarse combined waterfall for tuning 0..."
resumecmd -l ${LBL_BASELINEIMG0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py --baseline \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/baseline-${CMBPREFIX}-T0.png" \
   --label "${LABEL}_Low" "${WORK_DIR}/coarse-${CMBPREFIX}-T0.npy"
report_resumecmd
resumecmd -l ${LBL_SGBASELINEIMG0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py --baseline \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --savitzky-golay "${SG_PARAMS0[2]},${SG_PARAMS0[3]}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/SGbaseline-${CMBPREFIX}-T0.png" \
   --label "SG-${LABEL}_Low" "${WORK_DIR}/coarse-${CMBPREFIX}-T0.npy"
report_resumecmd

echo "radioreduce.sh: Generating bandpass images of coarse combined waterfall for tuning 1..."
resumecmd -l ${LBL_BANDPASSIMG1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/bandpass-${CMBPREFIX}-T1.png" \
   --label "${LABEL}_High" "${WORK_DIR}/coarse-${CMBPREFIX}-T1.npy"
report_resumecmd
resumecmd -l ${LBL_SGBANDPASSIMG1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --savitzky-golay "${SG_PARAMS1[0]},${SG_PARAMS1[1]}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/SGbandpass-${CMBPREFIX}-T1.png" \
   --label "SG-${LABEL}_High" "${WORK_DIR}/coarse-${CMBPREFIX}-T1.npy"
report_resumecmd
echo "radioreduce.sh: Generating baseline images of coarse combined waterfall for tuning 1..."
resumecmd -l ${LBL_BASELINEIMG1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py --baseline \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/baseline-${CMBPREFIX}-T1.png" \
   --label "${LABEL}_High" "${WORK_DIR}/coarse-${CMBPREFIX}-T1.npy"
report_resumecmd
resumecmd -l ${LBL_SGBASELINEIMG1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/bandpasscheck.py --baseline \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" \
   --savitzky-golay "${SG_PARAMS1[2]},${SG_PARAMS1[3]}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/SGbaseline-${CMBPREFIX}-T1.png" \
   --label "SG-${LABEL}_High" "${WORK_DIR}/coarse-${CMBPREFIX}-T1.npy"
report_resumecmd


# Create images of the coarse combined waterfalls for tuning 0 and tuning 1.
echo "radioreduce.sh: Generating coarse spectrogram image for tuning 0..."
resumecmd -l ${LBL_COARSEIMG0} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/watchwaterfall.py \
   --lower-FFT-index 0 --upper-FFT-index 4095 --label "${LABEL}_Low" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --rfi-std-cutoff ${RFI_STD} \
   --savitzky-golay "${SG_PARAMS0[0]},${SG_PARAMS0[1]},${SG_PARAMS0[2]},${SG_PARAMS0[3]}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/coarse-${CMBPREFIX}-T0.png" \
   --snr-cutoff ${SNR_CUTOFF} "${WORK_DIR}/coarse-${CMBPREFIX}-T0.npy"
report_resumecmd
echo "radioreduce.sh: Generating coarse spectrogram image for tuning 1..."
resumecmd -l ${LBL_COARSEIMG1} -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python ${INSTALL_DIR}/watchwaterfall.py \
   --lower-FFT-index 0 --upper-FFT-index 4095 --label "${LABEL}_High" \
   --commconfig "${WORK_DIR}/${COMMCONFIG_FILE}" --rfi-std-cutoff ${RFI_STD} \
   --savitzky-golay "${SG_PARAMS1[0]},${SG_PARAMS1[1]},${SG_PARAMS1[2]},${SG_PARAMS1[3]}" \
   --work-dir "${WORK_DIR}" --outfile "${WORK_DIR}/coarse-${CMBPREFIX}-T1.png" \
   --snr-cutoff ${SNR_CUTOFF} "${WORK_DIR}/coarse-${CMBPREFIX}-T1.npy"
report_resumecmd


# Delete the waterfall files and other temporary files from the working directory.  We shouldn't need
# them after this point.
echo "radioreduce.sh: Cleaning up temporary and intermediate files (this may take a few minutes)..."
resumecmd -l ${LBL_CLEAN} -k ${RESUME_LASTCMD_SUCCESS} \
   delete_files "${WORK_DIR}/*.dtmp"
report_resumecmd
if [ ${FLAG_DELWATERFALLS} -ne 0 ]; then
   echo "radioreduce.sh: Deleting waterfall files from working directory..."
   resumecmd -l ${LBL_DELWATERFALL} -k ${RESUME_LASTCMD_SUCCESS} \
      delete_files "${WORK_DIR}/waterfall*.npy"
   report_resumecmd
fi


# Determine exit status
if [ ${RESUME_LASTCMD_SUCCESS} -eq 1 ]; then
   echo "radioreduce.sh: Radio data reduction workflow completed successfully!"
   echo "radioreduce.sh: Workflow exiting with status 0."
   echo
   exit 0
else
   echo "radioreduce.sh: Radio data reduction workflow ended, but not all components were executed."
   echo "radioreduce.sh: Workflow exiting with status 1"
   echo
   exit 1
fi
