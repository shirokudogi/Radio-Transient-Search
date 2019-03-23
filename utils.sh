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
      if [ -f "${curr}" ]; then
         echo "Deleting ${curr}"
         rm -f "${curr}"
      else
         echo "${curr} not found or is not a file"
      fi
   done
   return 0
}
# end delete_files()


# Utility function to move all files from source directory to destination directory.
function transfer_files()
{
   local SRC_DIR="."
   local DEST_DIR="."
   local FILES=
   local RETVAL=0

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

   # Check that the source and destination directories exist before proceding further.
   if [ -d ${SRC_DIR} -a -d ${DEST_DIR} ]; then
      # Check if we have a list of files to transfer.
      if [ -z "${FILES[*]}" ]; then
         # If no particular files specified, then transfer everything in the source directory.
         FILES=$(basename -a ${SRC_DIR}/*)
      else
         # If we are not in the source directory, then we will need to make sure we have an explicit list
         # of all the files to be moved.
         if [[ $(pwd) != ${SRC_DIR} ]]; then
            pushd ${SRC_DIR} 1>/dev/null
            FILES=$(ls ./${FILES[*]} 2>/dev/null)
            popd 1>/dev/null
         fi
      fi

      if [[ "${SRC_DIR}" != "${DEST_DIR}" ]]; then
         echo "Transferring files from ${SRC_DIR} to ${DEST_DIR}..."
         for curr in ${FILES[*]}
         do
            echo "Moving ${curr}"
            mv ${SRC_DIR}/${curr} ${DEST_DIR}/${curr} 2>/dev/null
            if [ ${?} -ne 0 ]; then
               echo "Issue occurred moving ${SRC_DIR}/${curr} to ${DEST_DIR}/"
               RETVAL=1
            fi
         done
      fi
   else
      if [ ! -d ${SRC_DIR} ]; then
         echo "Source directory ${SRC_DIR} does not exist or is not a directory."
      fi
      if [ ! -d ${DEST_DIR} ]; then
         echo "Destination directory ${DEST_DIR} does not exist or is not a directory."
      fi
      RETVAL=1
   fi
   
   return ${RETVAL}
}
# end transfer_files()

# Menu selection function.
function menu_select ()
{
   local MENU_MESSAGE=
   local MENU_CHOICES=
   local CHOICE=-1   # By default, no choice has been made.
   local ARG_OPTS='^(--menu-message|-m)$'
   

   if [ ${#} -gt 0 ]; then
      # Parse arguments for the menu message and menu options.
      while [ -n "${1}" ]
      do
         if [[ "${1}" =~ ${ARG_OPTS} ]]; then
            MENU_MESSAGE="${2}"
            shift; shift
         else
            if [ ${#MENU_CHOICES[@]} -eq 1 ] && [ -z "${MENU_CHOICES}" ]; then
               MENU_CHOICES="${1}"
            else
               MENU_CHOICES=("${MENU_CHOICES[@]}" "${1}")
            fi
            shift
         fi
      done
      
      # Check that we have menu options.
      if [ ${#MENU_CHOICES[@]} -gt 0 ]; then
         # Display the menu message.
         echo "${MENU_MESSAGE}"

         # Display the menu and get the user's choice.
         OLD_IFS=${IFS}
         OLD_PS3="${PS3}"
         IFS=""
         PS3="Enter choice number: "
         select OPTION in ${MENU_CHOICES[@]}
         do
            # Determine user's selection.
            for i in ${!MENU_CHOICES[@]}
            do
               CURR="${MENU_CHOICES[${i}]}"
               if [ "${OPTION}" = "${CURR}" ]; then
                  CHOICE=${i}
               fi
            done
            if [ ${CHOICE} -ne -1 ]; then
               break
            fi
         done
         PS3="${OLD_PS3}"
         IFS=${OLD_IFS}
      fi
   fi

   return ${CHOICE}
}
# End function menu_select()
#
#
# CCY - This function is to be removed.  It's actually unnecessary and doesn't completely work the way I
# would like.  It will be retained in archive for future study.
#function parse_config()
#{
#   local CONFIG_FILE="${1}"
#   local COMMENT_PATTERN="^[[:space:]]*#"
#   local ARRAY_PATTERN1='^\(.+([[:space:]].+)+[[:space:]]*\)$'
#   local ARRAY_PATTERN2='^.+([[:space:]].+)+$'
#   local PRIOR_IFS=${IFS}
#   local varname=
#   local varvalue=
#
#   shopt -s extglob
#
#   if [ -z "${CONFIG_FILE}" ]; then
#      return 0
#   elif [ ! -f "${CONFIG_FILE}" ]; then
#      echo "Could not find configuration file ${CONFIG_FILE}"
#      return 1
#   else
#      IFS='='
#      while read -r varname varvalue
#      do
#         # If the line is not blank and not a comment, parse the variable and value pair.
#         if [[ -n ${varname} ]] && [[ ! ${varname} =~ ${COMMENT_PATTERN} ]]; then
#            varvalue=${varvalue%%\#*}  # Remove inline comments on the right.
#            varvalue=${varvalue%%*( )} # Remove trailing spaces.
#            varvalue=${varvalue#\"*}   # Remove opening quotation mark.
#            varvalue=${varvalue%\"*}   # Remove closing quotation mark.
#            # Determine if the value is an array.
#            if [[ ${varvalue} =~ ${ARRAY_PATTERN1} ]] || [[ ${varvalue} =~ ${ARRAY_PATTERN2} ]]; then
#               # If the array is enclosed in parentheses, remove the parentheses.
#               if [[ ${varvalue} =~ ${ARRAY_PATTERN1} ]]; then
#                  varvalue="${varvalue#\(*}"  # Remove opening parenthesis.
#                  varvalue="${varvalue%\)*}"  # Remove closing parenthesis.
#               fi
#               # Convert to bash array and export.
#               echo "got array ${varname} = ${varvalue}"
#               IFS=' '
#               varvalue=(${varvalue})
#               export ${varname}=${varvalue}
#               IFS='='
#            else
#               export ${varname}=${varvalue}
#            fi
#
#         fi
#      done < ${CONFIG_FILE}
#      IFS=${PRIOR_IFS}
#   fi
#
#   return 0
#}
