#!/bin/bash
#
# radiorun_example.sh
#
# PURPOSE: Example script for setting up a series of runs with radiotrans_run.sh
#

while [ ! -z "${1}" ]
do
   if [[ "${1}" == "--clean" ]]; then
      CLEAN_RUN_OPT="--clean"
   fi
   if [[ "${1}" == "--destroy" ]]; then
      DESTROY_OPT="--destroy"
   fi
   if [[ "${1}" == "--play-nice" ]]; then
      PLAY_NICE_OPT="--play-nice"
   fi
   shift
done

INSTALL_DIR="${HOME}/local/radiotrans"
WORK_ROOT="/mnt/toaster/cyancey"
RESULTS_ROOT="${HOME}/analysis"
DATA_UTILIZE=1.0                          # Fraction of data utilized to generate waterfalls.
#SEARCH_OPT="--do-dedispersed-search"     # Uncomment to enable de-dispersed search.
#SUPERCLUSTER_OPT="--supercluster"        # Uncomment to enable execution on supercluster (not tested)

# Add data filenames, run labels, and parameter paths in the arrays below.
DATA_FILENAMES=("057974_001488582")
LABELS=("GWR170809B2")
PARAMS_FILES=("./run_params.comm")

${INSTALL_DIR}/radiotrans_run.sh -I "${INSTALL_DIR}" -W "${WORK_ROOT}" -R "${RESULTS_ROOT}" \
                                 -D "${DATA_DIR}" ${CLEAN_RUN_OPT} ${DESTROY_OPT} ${PLAY_NICE_OPT} \
                                 ${SUPERCLUSTER_OPT} -U ${DATA_UTILIZE} \
                                 --GW170809 --delete-waterfalls --do-dedispersed-search \
                                 -A "${LABELS[0]}" "${DATA_FILENAMES[0]}" "${PARAMS_FILES[0]}"
