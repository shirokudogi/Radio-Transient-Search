#!/bin/bash
#
# radiorun_lwa.sh
#
# PURPOSE: Runs the radio transient search workflow on LWA.
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
# CCY - Remember to change these for V-Tech supercluster.
WORK_ROOT="/mnt/toaster/cyancey"
RESULTS_ROOT="${HOME}/analysis"
SUPERCLUSTER_OPT=
#SUPERCLUSTER_OPT="--supercluster"


DATA_FILENAMES=("057974_001488582")
LABELS=("GWR170809B2")
PARAM_FILE="./run_params.comm"

${INSTALL_DIR}/radiotrans_run.sh -I "${INSTALL_DIR}" -W "${WORK_ROOT}" -R "${RESULTS_ROOT}" \
                                 -P "${PARAM_FILE}" ${CLEAN_RUN_OPT} ${DESTROY_OPT} \
                                 --reload-work ${SUPERCLUSTER_OPT} ${PLAY_NICE_OPT} \
                                 --GW170809 --skip-reduce --do-dedispersed-search \
                                 -A "${LABELS[0]}" "${DATA_FILENAMES[0]}"
