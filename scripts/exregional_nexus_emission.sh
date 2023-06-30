#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. $USHdir/source_util_funcs.sh
source_config_for_task "cpl_aqm_parm|task_nexus_emission" ${GLOBAL_VAR_DEFNS_FP}
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; . $USHdir/preamble.sh; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( $READLINK -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that runs NEXUS.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Set OpenMP variables.
#
#-----------------------------------------------------------------------
#
export KMP_AFFINITY=${KMP_AFFINITY_NEXUS_EMISSION}
export OMP_NUM_THREADS=${OMP_NUM_THREADS_NEXUS_EMISSION}
export OMP_STACKSIZE=${OMP_STACKSIZE_NEXUS_EMISSION}
#
#-----------------------------------------------------------------------
#
# Set run command.
#
#-----------------------------------------------------------------------
#
eval ${PRE_TASK_CMDS}

nprocs=$(( NNODES_NEXUS_EMISSION*PPN_NEXUS_EMISSION ))
ppn_run_aqm="${PPN_NEXUS_EMISSION}"
omp_num_threads_run_aqm="${OMP_NUM_THREADS_NEXUS_EMISSION}"

if [ -z "${RUN_CMD_AQM:-}" ] ; then
  print_err_msg_exit "\
  Run command was not set in machine file. \
  Please set RUN_CMD_AQM for your platform"
else
  RUN_CMD_AQM=$(eval echo ${RUN_CMD_AQM})
  print_info_msg "$VERBOSE" "
  All executables will be submitted with command \'${RUN_CMD_AQM}\'."
fi

DATAinput="${DATA}/input"
mkdir -p "$DATAinput"
#
#-----------------------------------------------------------------------
#
# Link GFS surface data files to the tmp directory if they exist
#
#-----------------------------------------------------------------------
#
USE_GFS_SFC="FALSE"

if [ "${RUN_ENVIR}" = "nco" ]; then
  GFS_SFC_INPUT="${DATAROOT}/nexus_gfs_sfc.${share_pid}"
else
  GFS_SFC_INPUT="${COMIN}/GFS_SFC"
fi

if [ -d "${GFS_SFC_INPUT}" ]; then
  if [ "$(ls -A ${GFS_SFC_INPUT})" ]; then
    ln -sf "${GFS_SFC_INPUT}" "GFS_SFC"
    USE_GFS_SFC="TRUE"
  fi
fi

#
#-----------------------------------------------------------------------
#
# Copy the NEXUS config files to the tmp directory  
#
#-----------------------------------------------------------------------
#
cp ${EXECdir}/nexus ${DATA}
cp ${NEXUS_FIX_DIR}/${NEXUS_GRID_FN} ${DATA}/grid_spec.nc

if [ "${USE_GFS_SFC}" = "TRUE" ]; then
    cp ${ARL_NEXUS_DIR}/config/cmaq_gfs_megan/*.rc ${DATA}
else
    cp ${ARL_NEXUS_DIR}/config/cmaq/*.rc ${DATA}
fi
#
#-----------------------------------------------------------------------
#
# Get the starting and ending year, month, day, and hour of the emission
# time series.
#
#-----------------------------------------------------------------------
#
mm="${PDY:4:2}"
dd="${PDY:6:2}"
hh="${cyc}"
yyyymmdd="${PDY}"

NUM_SPLIT_NEXUS=$( printf "%02d" ${NUM_SPLIT_NEXUS} )
if [ ${#FCST_LEN_CYCL[@]} -gt 1 ]; then
  cyc_mod=$(( ${cyc} - ${DATE_FIRST_CYCL:8:2} ))
  CYCLE_IDX=$(( ${cyc_mod} / ${INCR_CYCL_FREQ} ))
  FCST_LEN_HRS=${FCST_LEN_CYCL[$CYCLE_IDX]}
fi

if [ "${NUM_SPLIT_NEXUS}" = "01" ]; then
  start_date=$( $DATE_UTIL --utc --date "${yyyymmdd} ${hh} UTC" "+%Y%m%d%H" )
  end_date=$( $DATE_UTIL --utc --date "${yyyymmdd} ${hh} UTC + ${FCST_LEN_HRS} hours" "+%Y%m%d%H" )
else
  len_per_split=$(( FCST_LEN_HRS / NUM_SPLIT_NEXUS  ))
  nsptp=$(( nspt+1 ))

  # Compute start and end dates for nexus split option
  start_del_hr=$(( len_per_split * nspt ))
  start_date=$( $DATE_UTIL --utc --date "${yyyymmdd} ${hh} UTC + ${start_del_hr} hours " "+%Y%m%d%H" )
  if [ "${nsptp}" = "${NUM_SPLIT_NEXUS}" ];then
    end_date=$( $DATE_UTIL --utc --date "${yyyymmdd} ${hh} UTC + $(expr $FCST_LEN_HRS + 1) hours" "+%Y%m%d%H" )
  else
    end_del_hr=$(( len_per_split * nsptp ))
    end_date=$( $DATE_UTIL --utc --date "${yyyymmdd} ${hh} UTC + $(expr $end_del_hr + 1) hours" "+%Y%m%d%H" )
  fi
fi
#
#######################################################################
# This will be the section to set the datasets used in $workdir/NEXUS_Config.rc 
# All Datasets in that file need to be placed here as it will link the files 
# necessary to that folder.  In the future this will be done by a get_nexus_input 
# script
NEI2016="TRUE"
TIMEZONES="TRUE"
CEDS="TRUE"
HTAP2010="TRUE"
OMIHTAP="TRUE"
MASKS="TRUE"
NOAAGMD="TRUE"
SOA="TRUE"
EDGAR="TRUE"
MEGAN="TRUE"
MODIS_XLAI="TRUE"
OLSON_MAP="TRUE"
Yuan_XLAI="TRUE"
GEOS="TRUE"
AnnualScalar="TRUE"

NEXUS_INPUT_BASE_DIR=${NEXUS_INPUT_DIR}
########################################################################

#
#----------------------------------------------------------------------
# 
# modify time configuration file
#
python3 ${ARL_NEXUS_DIR}/utils/python/nexus_time_parser.py -f ${DATA}/HEMCO_sa_Time.rc -s $start_date -e $end_date
export err=$?
if [ $err -ne 0 ]; then
  message_txt="Call to python script \"nexus_time_parser.py\" failed."
  if [ "${RUN_ENVIR}" = "community" ]; then
    print_err_msg_exit "${message_txt}"
  else
    err_exit "${message_txt}"
  fi
fi
#
#---------------------------------------------------------------------
#
# set the root directory to the temporary directory
#
python3 ${ARL_NEXUS_DIR}/utils/python/nexus_root_parser.py -f ${DATA}/NEXUS_Config.rc -d ${DATAinput}
export err=$?
if [ $err -ne 0 ]; then
  message_txt="Call to python script \"nexus_root_parser.py\" failed."
  if [ "${RUN_ENVIR}" = "community" ]; then
    print_err_msg_exit "${message_txt}"
  else
    err_exit "${message_txt}"
  fi
fi
#
#----------------------------------------------------------------------
# Get all the files needed (TEMPORARILY JUST COPY FROM THE DIRECTORY)
#
if [ "${NEI2016}" = "TRUE" ]; then #NEI2016
  mkdir -p ${DATAinput}/NEI2016v1
  mkdir -p ${DATAinput}/NEI2016v1/v2022-07
  mkdir -p ${DATAinput}/NEI2016v1/v2022-07/${mm}
  python3 ${ARL_NEXUS_DIR}/utils/python/nexus_nei2016_linker.py --src_dir ${NEXUS_INPUT_BASE_DIR} --date ${yyyymmdd} --work_dir ${DATAinput} -v "v2022-07"
  export err=$?
  if [ $err -ne 0 ]; then
    message_txt="Call to python script \"nexus_nei2016_linker.py\" failed."
    if [ "${RUN_ENVIR}" = "community" ]; then
      print_err_msg_exit "${message_txt}"
    else
      err_exit "${message_txt}"
    fi
  fi

  python3 ${ARL_NEXUS_DIR}/utils/python/nexus_nei2016_control_tilefix.py -f ${DATA}/NEXUS_Config.rc -t ${DATA}/HEMCO_sa_Time.rc # -d ${yyyymmdd}
  export err=$?
  if [ $err -ne 0 ]; then
    message_txt="Call to python script \"nexus_nei2016_control_tilefix.py\" failed."
    if [ "${RUN_ENVIR}" = "community" ]; then
      print_err_msg_exit "${message_txt}"
    else
      err_exit "${message_txt}"
    fi
  fi
fi

if [ "${TIMEZONES}" = "TRUE" ]; then # TIME ZONES
  ln -sf ${NEXUS_INPUT_BASE_DIR}/TIMEZONES ${DATAinput}
fi

if [ "${MASKS}" = "TRUE" ]; then # MASKS
  ln -sf ${NEXUS_INPUT_BASE_DIR}/MASKS ${DATAinput}
fi

if [ "${CEDS}" = "TRUE" ]; then #CEDS
  ln -sf ${NEXUS_INPUT_BASE_DIR}/CEDS ${DATAinput}
fi

if [ "${HTAP2010}" = "TRUE" ]; then #CEDS2014
  ln -sf ${NEXUS_INPUT_BASE_DIR}/HTAP ${DATAinput}
fi

if [ "${OMIHTAP}" = "TRUE" ]; then #CEDS2014
  ln -sf ${NEXUS_INPUT_BASE_DIR}/OMI-HTAP_2019 ${DATAinput}
fi

if [ "${NOAAGMD}" = "TRUE" ]; then #NOAA_GMD
  ln -sf ${NEXUS_INPUT_BASE_DIR}/NOAA_GMD ${DATAinput}
fi

if [ "${SOA}" = "TRUE" ]; then #SOA
  ln -sf ${NEXUS_INPUT_BASE_DIR}/SOA ${DATAinput}
fi

if [ "${EDGAR}" = "TRUE" ]; then #EDGARv42
  ln -sf ${NEXUS_INPUT_BASE_DIR}/EDGARv42 ${DATAinput}
fi

if [ "${MEGAN}" = "TRUE" ]; then #MEGAN
  ln -sf ${NEXUS_INPUT_BASE_DIR}/MEGAN ${DATAinput}
fi

if [ "${OLSON_MAP}" = "TRUE" ]; then #OLSON_MAP
  ln -sf ${NEXUS_INPUT_BASE_DIR}/OLSON_MAP ${DATAinput}
fi

if [ "${Yuan_XLAI}" = "TRUE" ]; then #Yuan_XLAI
  ln -sf ${NEXUS_INPUT_BASE_DIR}/Yuan_XLAI ${DATAinput}
fi

if [ "${GEOS}" = "TRUE" ]; then #GEOS
  ln -sf ${NEXUS_INPUT_BASE_DIR}/GEOS_0.5x0.625 ${DATAinput}
fi

if [ "${AnnualScalar}" = "TRUE" ]; then #ANNUAL_SCALAR
  ln -sf ${NEXUS_INPUT_BASE_DIR}/AnnualScalar ${DATAinput}
fi

if [ "${MODIS_XLAI}" = "TRUE" ]; then #MODIS_XLAI
  ln -sf ${NEXUS_INPUT_BASE_DIR}/MODIS_XLAI ${DATAinput}
fi

if [ "${USE_GFS_SFC}" = "TRUE" ]; then # GFS INPUT
  mkdir -p ${DATAinput}/GFS_SFC
  python3 ${ARL_NEXUS_DIR}/utils/python/nexus_gfs_bio.py -i ${DATA}/GFS_SFC/gfs.t??z.sfcf???.nc -o ${DATA}/GFS_SFC_MEGAN_INPUT.nc
  export err=$?
  if [ $err -ne 0 ]; then
    message_txt="Call to python script \"nexus_gfs_bio.py\" failed."
    if [ "${RUN_ENVIR}" = "community" ]; then
      print_err_msg_exit "${message_txt}"
    else
      err_exit "${message_txt}"
    fi
  fi
fi

#
#----------------------------------------------------------------------
#
# Execute NEXUS
#
#-----------------------------------------------------------------------
#
PREP_STEP
eval ${RUN_CMD_AQM} ${EXECdir}/nexus -c NEXUS_Config.rc -r grid_spec.nc -o NEXUS_Expt_split.nc ${REDIRECT_OUT_ERR}
export err=$?
if [ "${RUN_ENVIR}" = "nco" ]; then
  err_chk
else
  if [ $err -ne 0 ]; then
    print_err_msg_exit "Call to execute nexus standalone for the FV3LAM failed."
  fi
fi
POST_STEP

# 
#-----------------------------------------------------------------------
#
# make nexus output pretty and move to INPUT_DATA directory
#
#-----------------------------------------------------------------------
#
python3 ${ARL_NEXUS_DIR}/utils/python/make_nexus_output_pretty.py --src ${DATA}/NEXUS_Expt_split.nc --grid ${DATA}/grid_spec.nc -o ${INPUT_DATA}/${NET}.${cycle}${dot_ensmem}.NEXUS_Expt_split.${nspt}.nc -t ${DATA}/HEMCO_sa_Time.rc
export err=$?
if [ $err -ne 0 ]; then
  message_txt="Call to python script \"make_nexus_output_pretty.py\" failed."
  if [ "${RUN_ENVIR}" = "community" ]; then
    print_err_msg_exit "${message_txt}"
  else
    err_exit "${message_txt}"
  fi
fi
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
NEXUS has successfully generated emissions files in netcdf format!!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1
