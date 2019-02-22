#!/bin/bash
#
# utils.sh
#
# Created by:     Cregg C. Yancey
# Creation date:  October 11 2018
#
# Modified by:
# Modified date:
#
# PURPOSE: Implement utility functions used in shell scripts.
#

# Utility function for deleting specified files.
function delete_files()
{
   local FILES=("${@}")

   for curr in ${FILES[*]}
   do
      rm -f "${curr}"
   done
}
# end delete_files()


# Utility function to move all files from source directory to destination directory.
function transfer_files()
{
   local SRC_DIR="."
   local DEST_DIR="."
   local FILES=

   # Parse commandline.
   if [ ${#} -gt 0 ]; then
      while [ -n "${1}" ]
      do
         case "${1}" in
            -s | --src-dir)
               SRC_DIR="${2}"
               shift; shift
               ;;
            -d | --dest-dir)
               DEST_DIR="${2}"
               shift; shift
               ;;
            *)
               FILES=("${*}")
               break
               ;;
         esac
      done
   fi

   # Check if we have a list of files to transfer.
   if [ -z "${FILES}" ]; then
      FILES=$(basename "${SRC_DIR}/*")
   else
      # If we are not in the source directory, then we will need to make sure we have an explicit list
      # of all the files to be moved.
      if [[ $(pwd) != "${SRC_DIR}" ]]; then
         CURR_DIR=$(pwd)
         cd "${SRC_DIR}"
         FILES=$(ls ${FILES[*]})
         cd "${CURR_DIR}"
      fi
   fi

   if [[ "${SRC_DIR}" != "${DEST_DIR}" ]]; then
      echo "Transferring files from ${SRC_DIR} to ${DEST_DIR}..."
      for curr in ${FILES[*]}
      do
         echo "Moving ${curr}"
         mv "${SRC_DIR}/${curr}" "${DEST_DIR}/${curr}"
      done
   fi
}
# end transfer_files()
