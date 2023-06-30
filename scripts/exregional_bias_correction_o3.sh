#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. $USHdir/source_util_funcs.sh
source_config_for_task "cpl_aqm_parm|task_bias_correction_o3" ${GLOBAL_VAR_DEFNS_FP}
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
This is the ex-script for the task that runs BIAS-CORRECTION-O3.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Set OpenMP variables.
#
#-----------------------------------------------------------------------
#
export KMP_AFFINITY=${KMP_AFFINITY_BIAS_CORRECTION_O3}
export OMP_NUM_THREADS=${OMP_NUM_THREADS_BIAS_CORRECTION_O3}
export OMP_STACKSIZE=${OMP_STACKSIZE_BIAS_CORRECTION_O3}
export OMP_PLACES=cores
#
#-----------------------------------------------------------------------
#
# Set run command.
#
#-----------------------------------------------------------------------
#
eval ${PRE_TASK_CMDS}

if [ -z "${RUN_CMD_SERIAL:-}" ] ; then
  print_err_msg_exit "\
  Run command was not set in machine file. \
  Please set RUN_CMD_SERIAL for your platform"
else
  RUN_CMD_SERIAL=$(eval echo ${RUN_CMD_SERIAL})
  print_info_msg "$VERBOSE" "
  All executables will be submitted with command \'${RUN_CMD_SERIAL}\'."
fi

yyyy=${PDY:0:4}
yyyymm=${PDY:0:6}
yyyy_m1=${PDYm1:0:4}
yyyymm_m1=${PDYm1:0:6}
yyyy_m2=${PDYm2:0:4}
yyyymm_m2=${PDYm2:0:6}
yyyy_m3=${PDYm3:0:4}
yyyymm_m3=${PDYm3:0:6}
 
#
#-----------------------------------------------------------------------
#
# Bias correction: O3
#
#-----------------------------------------------------------------------
#
if [ "${PREDEF_GRID_NAME}" = "AQM_NA_13km" ]; then
  id_domain=793
fi

if [ ${#FCST_LEN_CYCL[@]} -gt 1 ]; then
  cyc_mod=$(( ${cyc} - ${DATE_FIRST_CYCL:8:2} ))
  CYCLE_IDX=$(( ${cyc_mod} / ${INCR_CYCL_FREQ} ))
  FCST_LEN_HRS=${FCST_LEN_CYCL[$CYCLE_IDX]}
fi

#-----------------------------------------------------------------------------
# STEP 1: Retrieve AIRNOW observation data
#-----------------------------------------------------------------------------

mkdir -p "${DATA}/data"

# Retrieve real-time airnow data for the last three days and convert them into netcdf
  for ipdym in {1..3}; do
    case $ipdym in
      1)
        cvt_yyyy="${yyyy_m1}"
        cvt_yyyymm="${yyyymm_m1}"
        cvt_pdy="${PDYm1}"
        ;;
      2)
        cvt_yyyy="${yyyy_m2}"
        cvt_yyyymm="${yyyymm_m2}"
        cvt_pdy="${PDYm2}"
        ;;
      3)
        cvt_yyyy="${yyyy_m3}"
        cvt_yyyymm="${yyyymm_m3}"
        cvt_pdy="${PDYm3}"
        ;;
    esac

    cvt_input_dir="${DATA}/data/bcdata.${cvt_yyyymm}/airnow/csv"
    cvt_output_dir="${DATA}/data/bcdata.${cvt_yyyymm}/airnow/netcdf"
    cvt_input_fn="HourlyAQObs_YYYYMMDDHH.dat"
    cvt_output_fn="HourlyAQObs.YYYYMMDD.nc"
    cvt_input_fp="${cvt_input_dir}/YYYY/YYYYMMDD/${cvt_input_fn}"
    cvt_output_fp="${cvt_output_dir}/YYYY/YYYYMMDD/${cvt_output_fn}"

    mkdir -p "${cvt_input_dir}/${cvt_yyyy}/${cvt_pdy}"
    mkdir -p "${cvt_output_dir}/${cvt_yyyy}/${cvt_pdy}"
    cp ${DCOMINairnow}/${cvt_pdy}/airnow/HourlyAQObs_${cvt_pdy}*.dat "${cvt_input_dir}/${cvt_yyyy}/${cvt_pdy}"

    PREP_STEP
    eval ${RUN_CMD_SERIAL} ${EXECdir}/convert_airnow_csv ${cvt_input_fp} ${cvt_output_fp} ${cvt_pdy} ${cvt_pdy} ${REDIRECT_OUT_ERR}
    export err=$?
    if [ "${RUN_ENVIR}" = "nco" ]; then
      err_chk
    else
      if [ $err -ne 0 ]; then
        print_err_msg_exit "Call to executable to run CONVERT_AIRNOW_CSV returned with nonzero exit code."
      fi
    fi
    POST_STEP
  done     

#-----------------------------------------------------------------------------
# STEP 2:  Extracting PM2.5, O3, and met variables from CMAQ input and outputs
#-----------------------------------------------------------------------------

FCST_LEN_HRS=$( printf "%03d" ${FCST_LEN_HRS} )
ic=1
while [ $ic -lt 120 ]; do
  if [ -s ${COMIN}/${NET}.${cycle}.chem_sfc.f${FCST_LEN_HRS}.nc ]; then
    echo "cycle ${cyc} post1 is done!"
    break
  else
    (( ic=ic+1 ))
  fi
done

if [ $ic -ge 120 ]; then
  print_err_msg_exit "FATAL ERROR - COULD NOT LOCATE:${NET}.${cycle}.chem_sfc.f${FCST_LEN_HRS}.nc"
fi

# remove any pre-exit ${NET}.${cycle}.chem_sfc/met_sfc.nc for 2-stage post processing
DATA_grid="${DATA}/data/bcdata.${yyyymm}/grid"
if [ -d "${DATA_grid}/${cyc}z/${PDY}" ]; then
  rm -rf "${DATA_grid}/${cyc}z/${PDY}"
fi

mkdir -p "${DATA_grid}/${cyc}z/${PDY}"
ln -sf ${COMIN}/${NET}.${cycle}.chem_sfc.*.nc ${DATA_grid}/${cyc}z/${PDY}
ln -sf ${COMIN}/${NET}.${cycle}.met_sfc.*.nc ${DATA_grid}/${cyc}z/${PDY}

#-----------------------------------------------------------------------------
# STEP 3:  Intepolating CMAQ O3 into AIRNow sites
#-----------------------------------------------------------------------------

mkdir -p ${DATA}/data/coords 
mkdir -p ${DATA}/data/site-lists.interp 
mkdir -p ${DATA}/out/ozone/${yyyy}
mkdir -p ${DATA}/data/bcdata.${yyyymm}/interpolated/ozone/${yyyy} 

cp ${PARMaqm_utils}/bias_correction/sites.valid.ozone.20230331.12z.list ${DATA}/data/site-lists.interp
cp ${PARMaqm_utils}/bias_correction/aqm.t12z.chem_sfc.f000.nc ${DATA}/data/coords
cp ${PARMaqm_utils}/bias_correction/config.interp.ozone.7-vars_${id_domain}.${cyc}z ${DATA}

PREP_STEP
eval ${RUN_CMD_SERIAL} ${EXECdir}/aqm_bias_interpolate config.interp.ozone.7-vars_${id_domain}.${cyc}z ${cyc}z ${PDY} ${PDY} ${REDIRECT_OUT_ERR}
export err=$?
if [ "${RUN_ENVIR}" = "nco" ]; then
  err_chk
else
  if [ $err -ne 0 ]; then
    print_err_msg_exit "Call to executable to run AQM_BIAS_INTERPOLATE returned with nonzero exit code."
  fi
fi
POST_STEP

cp ${DATA}/out/ozone/${yyyy}/*nc ${DATA}/data/bcdata.${yyyymm}/interpolated/ozone/${yyyy}

if [ "${DO_AQM_SAVE_AIRNOW_HIST}" = "TRUE" ]; then
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm}/interpolated/ozone/${yyyy}
  cp ${DATA}/out/ozone/${yyyy}/*nc ${COMOUTbicor}/bcdata.${yyyymm}/interpolated/ozone/${yyyy}

  # CSV files
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm}/airnow/csv/${yyyy}/${PDY}
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm_m1}/airnow/csv/${yyyy_m1}/${PDYm1}
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm_m2}/airnow/csv/${yyyy_m2}/${PDYm2}
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm_m3}/airnow/csv/${yyyy_m3}/${PDYm3}
  cp ${DCOMINairnow}/${PDYm1}/airnow/HourlyAQObs_${PDYm1}*.dat ${COMOUTbicor}/bcdata.${yyyymm_m1}/airnow/csv/${yyyy_m1}/${PDYm1}  
  cp ${DCOMINairnow}/${PDYm2}/airnow/HourlyAQObs_${PDYm2}*.dat ${COMOUTbicor}/bcdata.${yyyymm_m2}/airnow/csv/${yyyy_m2}/${PDYm2}  
  cp ${DCOMINairnow}/${PDYm3}/airnow/HourlyAQObs_${PDYm3}*.dat ${COMOUTbicor}/bcdata.${yyyymm_m3}/airnow/csv/${yyyy_m3}/${PDYm3}

  # NetCDF files
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm}/airnow/netcdf/${yyyy}/${PDY}
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm_m1}/airnow/netcdf/${yyyy_m1}/${PDYm1}
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm_m2}/airnow/netcdf/${yyyy_m2}/${PDYm2}
  mkdir -p ${COMOUTbicor}/bcdata.${yyyymm_m3}/airnow/netcdf/${yyyy_m3}/${PDYm3}
  cp ${DATA}/data/bcdata.${yyyymm_m1}/airnow/netcdf/${yyyy_m1}/${PDYm1}/HourlyAQObs.${PDYm1}.nc ${COMOUTbicor}/bcdata.${yyyymm_m1}/airnow/netcdf/${yyyy_m1}/${PDYm1}  
  cp ${DATA}/data/bcdata.${yyyymm_m2}/airnow/netcdf/${yyyy_m2}/${PDYm2}/HourlyAQObs.${PDYm2}.nc ${COMOUTbicor}/bcdata.${yyyymm_m2}/airnow/netcdf/${yyyy_m2}/${PDYm2}  
  cp ${DATA}/data/bcdata.${yyyymm_m3}/airnow/netcdf/${yyyy_m3}/${PDYm3}/HourlyAQObs.${PDYm3}.nc ${COMOUTbicor}/bcdata.${yyyymm_m3}/airnow/netcdf/${yyyy_m3}/${PDYm3}

  mkdir -p  "${COMOUTbicor}/bcdata.${yyyymm}/grid/${cyc}z/${PDY}"
  cp ${COMIN}/${NET}.${cycle}.*sfc*.nc ${COMOUTbicor}/bcdata.${yyyymm}/grid/${cyc}z/${PDY}
fi

#-----------------------------------------------------------------------------
# STEP 4:  Performing Bias Correction for Ozone
#-----------------------------------------------------------------------------

rm -rf ${DATA}/data/bcdata*

ln -sf ${COMINbicor}/bcdata* "${DATA}/data"

mkdir -p ${DATA}/data/sites
cp ${PARMaqm_utils}/bias_correction/config.ozone.bias_corr_${id_domain}.${cyc}z ${DATA}

PREP_STEP
eval ${RUN_CMD_SERIAL} ${EXECdir}/aqm_bias_correct config.ozone.bias_corr_${id_domain}.${cyc}z ${cyc}z ${BC_STDAY} ${PDY} ${REDIRECT_OUT_ERR}
export err=$?
if [ "${RUN_ENVIR}" = "nco" ]; then
  err_chk
else
  if [ $err -ne 0 ]; then
    print_err_msg_exit "Call to executable to run AQM_BIAS_CORRECT returned with nonzero exit code."
  fi
fi
POST_STEP

cp ${DATA}/out/ozone.corrected* ${COMIN}

if [ "${cyc}" = "12" ]; then
  cp ${DATA}/data/sites/sites.valid.ozone.${PDY}.${cyc}z.list ${DATA}
fi

#-----------------------------------------------------------------------------
# STEP 5:  converting netcdf to grib format
#-----------------------------------------------------------------------------

ln -sf ${COMIN}/ozone.corrected.${PDY}.${cyc}z.nc .

#
cat >bias_cor.ini <<EOF1
&control
varlist='o3','O3_8hr'
infile='ozone.corrected.${PDY}.${cyc}z.nc'
outfile='${NET}.${cycle}.awpozcon_bc'
id_gribdomain=${id_domain}
/
EOF1

# convert from netcdf to grib2 format
PREP_STEP
eval ${RUN_CMD_SERIAL} ${EXECdir}/aqm_post_bias_cor_grib2 ${PDY} ${cyc} ${REDIRECT_OUT_ERR}
export err=$?
if [ "${RUN_ENVIR}" = "nco" ]; then
  err_chk
else
  if [ $err -ne 0 ]; then
    print_err_msg_exit "Call to executable to run AQM_POST_BIAS_COR_GIRB2 returned with nonzero exit code."
  fi
fi
POST_STEP

cp ${DATA}/${NET}.${cycle}.awpozcon*bc*.grib2 ${COMOUT}

#-----------------------------------------------------------------------------
# STEP 6: calculating 24-hr ave PM2.5
#-----------------------------------------------------------------------------

if [ "${cyc}" = "06" ] || [ "${cyc}" = "12" ]; then
  ln -sf ${COMOUT}/ozone.corrected.${PDY}.${cyc}z.nc a.nc 

  chk=1 
  chk1=1 
  # today 00z file exists otherwise chk=0
cat >bias_cor_max.ini <<EOF1
&control
varlist='O3_1h_max','O3_8h_max'
outfile='aqm-maxi_bc'
id_gribdomain=${id_domain}
max_proc=72
/
EOF1

  flag_run_bicor_max=yes
  # 06z needs b.nc to find current day output from 04Z to 06Z
  if [ "${cyc}" = "06" ]; then
    if [ -s ${COMIN}/../00/ozone.corrected.${PDY}.00z.nc ]; then
      ln -sf ${COMIN}/../00/ozone.corrected.${PDY}.00z.nc b.nc
    elif [ -s ${COMINm1}/12/ozone.corrected.${PDYm1}.12z.nc ]; then
      ln -sf ${COMINm1}/12/ozone.corrected.${PDYm1}.12z.nc b.nc
      chk=0
    else
      flag_run_bicor_max=no
    fi
  fi

  if [ "${cyc}" = "12" ]; then
    # 12z needs b.nc to find current day output from 04Z to 06Z
    if [ -s ${COMIN}/../00/ozone.corrected.${PDY}.00z.nc ]; then
      ln -sf ${COMIN}/../00/ozone.corrected.${PDY}.00z.nc b.nc
    elif [ -s ${COMINm1}/12/ozone.corrected.${PDYm1}.12z.nc ]; then
      ln -sf ${COMINm1}/12/ozone.corrected.${PDYm1}.12z.nc b.nc
      chk=0
    else
      flag_run_bicor_max=no
    fi

    # 12z needs c.nc to find current day output from 07Z to 12z
    if [ -s ${COMIN}/../06/ozone.corrected.${PDY}.06z.nc ]; then
      ln -sf ${COMIN}/../06/ozone.corrected.${PDY}.06z.nc c.nc
    elif [ -s ${COMINm1}/12/ozone.corrected.${PDYm1}.12z.nc ]; then
      ln -sf ${COMINm1}/12/ozone.corrected.${PDYm1}.12z.nc c.nc
      chk1=0
    else
      flag_run_bicor_max=no
    fi
  fi

  if [ "${flag_run_bicor_max}" = "yes" ]; then
    #-------------------------------------------------
    # write out grib2 format 
    #-------------------------------------------------
    PREP_STEP
    eval ${RUN_CMD_SERIAL} ${EXECdir}/aqm_post_maxi_bias_cor_grib2  ${PDY} ${cyc} ${chk} ${chk1} ${REDIRECT_OUT_ERR}
    export err=$?
    if [ "${RUN_ENVIR}" = "nco" ]; then
      err_chk
    else
      if [ $err -ne 0 ]; then
        print_err_msg_exit "Call to executable to run AQM_POST_MAXI_BIAS_COR_GRIB2 returned with nonzero exit code."
      fi
    fi
    POST_STEP

    # split into max_1h and max_8h files and copy to grib227
    wgrib2 aqm-maxi_bc.${id_domain}.grib2 |grep "OZMAX1" | wgrib2 -i aqm-maxi_bc.${id_domain}.grib2 -grib  ${NET}.${cycle}.max_1hr_o3_bc.${id_domain}.grib2
    wgrib2 aqm-maxi_bc.${id_domain}.grib2 |grep "OZMAX8" | wgrib2 -i aqm-maxi_bc.${id_domain}.grib2 -grib  ${NET}.${cycle}.max_8hr_o3_bc.${id_domain}.grib2

    grid227="lambert:265.0000:25.0000:25.0000 226.5410:1473:5079.000 12.1900:1025:5079.000"
   
    wgrib2 ${NET}.${cycle}.max_8hr_o3_bc.${id_domain}.grib2 -set_grib_type c3b -new_grid_winds earth -new_grid ${grid227} ${NET}.${cycle}.max_8hr_o3_bc.227.grib2
    wgrib2 ${NET}.${cycle}.max_1hr_o3_bc.${id_domain}.grib2 -set_grib_type c3b -new_grid_winds earth -new_grid ${grid227} ${NET}.${cycle}.max_1hr_o3_bc.227.grib2

    cp ${DATA}/${NET}.${cycle}.max_*hr_o3_bc.*.grib2 ${COMOUT}
   
    if [ "$SENDDBN" = "TRUE" ]; then
      ${DBNROOT}/bin/dbn_alert MODEL AQM_MAX ${job} ${COMOUT}/${NET}.${cycle}.max_1hr_o3_bc.227.grib2
      ${DBNROOT}/bin/dbn_alert MODEL AQM_MAX ${job} ${COMOUT}/${NET}.${cycle}.max_8hr_o3_bc.227.grib2
    fi
   
    # Add WMO header for daily 1h and 8h max O3 
    for hr in 1 8; do
      echo 0 > filesize
      export XLFRTEOPTS="unit_vars=yes"
      export FORT11=${NET}.${cycle}.max_${hr}hr_o3_bc.227.grib2
      export FORT12="filesize"
      export FORT31=
      export FORT51=${NET}-${hr}hro3-maxi.227.grib2.temp
      tocgrib2super < ${PARMaqm_utils}/wmo/grib2_aqm-${hr}hro3-maxi.${cycle}.227
   
      echo `ls -l ${NET}-${hr}hro3-maxi.227.grib2.temp | awk '{print $5} '` > filesize
      export XLFRTEOPTS="unit_vars=yes"
      export FORT11=${NET}-${hr}hro3-maxi.227.grib2.temp
      export FORT12="filesize"
      export FORT31=
      export FORT51=awpaqm.${cycle}.${hr}ho3-max-bc.227.grib2
      tocgrib2super < ${PARMaqm_utils}/wmo/grib2_aqm-${hr}hro3-maxi.${cycle}.227
    done
   
    # Post Files to COMOUTwmo
    cp awpaqm.${cycle}.*o3-max-bc.227.grib2 ${COMOUTwmo}

    # Distribute Data
    if [ "${SENDDBN_NTC}" = "TRUE" ] ; then
      ${DBNROOT}/bin/dbn_alert ${DBNALERT_TYPE} ${NET} ${job} ${COMOUTwmo}/awpaqm.${cycle}.1ho3-max-bc.227.grib2
      ${DBNROOT}/bin/dbn_alert ${DBNALERT_TYPE} ${NET} ${job} ${COMOUTwmo}/awpaqm.${cycle}.8ho3-max-bc.227.grib2
    fi
  fi
fi

#-------------------------------------
rm -rf tmpfile

fhr=01
while [ "${fhr}" -le "${FCST_LEN_HRS}" ]; do
  fhr3d=$( printf "%03d" "${fhr}" )
  
  cp ${DATA}/${NET}.${cycle}.awpozcon_bc.f${fhr3d}.${id_domain}.grib2 ${COMOUT}

  # create GRIB file to convert to grid 227 then to GRIB2 for NDFD
  cat ${DATA}/${NET}.${cycle}.awpozcon_bc.f${fhr3d}.${id_domain}.grib2 >> tmpfile
  if [ "${fhr}" -le "07" ]; then
    cat ${DATA}/${NET}.${cycle}.awpozcon_bc.f${fhr3d}.${id_domain}.grib2 >> tmpfile.1hr
  else
    wgrib2 ${DATA}/${NET}.${cycle}.awpozcon_bc.f${fhr3d}.${id_domain}.grib2 -d 1 -append -grib tmpfile.1hr
    wgrib2 ${DATA}/${NET}.${cycle}.awpozcon_bc.f${fhr3d}.${id_domain}.grib2 -d 2 -append -grib tmpfile.8hr
  fi
  (( fhr=fhr+1 ))
done

###############
# Convert ozone Concentration to grid 227 in GRIB2 format
###############
echo ' &NLCOPYGB IDS(180)=1, /' > ozcon_scale

newgrib2file1=${NET}.${cycle}.ave_1hr_o3_bc.227.grib2
newgrib2file2=${NET}.${cycle}.ave_8hr_o3_bc.227.grib2

grid227="lambert:265.0000:25.0000:25.0000 226.5410:1473:5079.000 12.1900:1025:5079.000"

wgrib2 tmpfile.1hr -set_grib_type c3b -new_grid_winds earth -new_grid ${grid227} ${newgrib2file1} 
cp tmpfile.1hr ${COMOUT}/${NET}.${cycle}.ave_1hr_o3_bc.${id_domain}.grib2
cp ${NET}.${cycle}.ave_1hr_o3_bc.227.grib2 ${COMOUT}

if [ "${cyc}" = "06" ] || [ "${cyc}" = "12" ]; then
  wgrib2 tmpfile.8hr -set_grib_type c3b -new_grid_winds earth -new_grid ${grid227} ${newgrib2file2} 
  cp tmpfile.8hr ${COMOUT}/${NET}.${cycle}.ave_8hr_o3_bc.${id_domain}.grib2
  cp ${NET}.${cycle}.ave_8hr_o3_bc.227.grib2 ${COMOUT}
fi

if [ "${SENDDBN}" = "TRUE" ] ; then
   ${DBNROOT}/bin/dbn_alert MODEL AQM_CONC ${job} ${COMOUT}/${NET}.${cycle}.ave_1hr_o3_bc.227.grib2
  if [ "${cyc}" = "06" ] || [ "${cyc}" = "12" ]; then
   ${DBNROOT}/bin/dbn_alert MODEL AQM_CONC ${job} ${COMOUT}/${NET}.${cycle}.ave_8hr_o3_bc.227.grib2
  fi
fi

#################################################
#    Part III:  Insert WMO header to GRIB files
#################################################

if [ "${cyc}" = "06" ] || [ "${cyc}" = "12" ]; then
  # Create AWIPS GRIB data for 1hr and 8hr ave ozone
  for hr in 1 8; do
    echo 0 > filesize
    export XLFRTEOPTS="unit_vars=yes"
    export FORT11=${NET}.${cycle}.ave_${hr}hr_o3_bc.227.grib2
    export FORT12="filesize"
    export FORT31=
    export FORT51=grib2.${cycle}.awpcsozcon_aqm_${hr}-bc.temp
    tocgrib2super < ${PARMaqm_utils}/wmo/grib2_aqm_ave_${hr}hr_o3_bc-awpozcon.${cycle}.227

    echo `ls -l grib2.${cycle}.awpcsozcon_aqm_${hr}-bc.temp  | awk '{print $5} '` > filesize
    export XLFRTEOPTS="unit_vars=yes"
    export FORT11=grib2.${cycle}.awpcsozcon_aqm_${hr}-bc.temp
    export FORT12="filesize"
    export FORT31=
    export FORT51=awpaqm.${cycle}.${hr}ho3-bc.227.grib2
    tocgrib2super < ${PARMaqm_utils}/wmo/grib2_aqm_ave_${hr}hr_o3_bc-awpozcon.${cycle}.227

    # Create AWIPS GRIB data for dailly 1-hr and 8hr max ozone
    echo 0 > filesize
    export XLFRTEOPTS="unit_vars=yes"
    export FORT11=${NET}.${cycle}.max_${hr}hr_o3_bc.227.grib2
    export FORT12="filesize"
    export FORT31=
    export FORT51=${NET}.${cycle}.max_${hr}hr_o3-bc.227.grib2.temp
    tocgrib2super < ${PARMaqm_utils}/wmo/grib2_aqm-${hr}hro3_bc-maxi.${cycle}.227

    echo `ls -l  ${NET}.${cycle}.max_${hr}hr_o3-bc.227.grib2.temp | awk '{print $5} '` > filesize
    export XLFRTEOPTS="unit_vars=yes"
    export FORT11=${NET}.${cycle}.max_${hr}hr_o3-bc.227.grib2.temp
    export FORT12="filesize"
    export FORT31=
    export FORT51=awpaqm.${cycle}.${hr}ho3-max-bc.227.grib2
    tocgrib2super < ${PARMaqm_utils}/wmo/grib2_aqm-${hr}hro3_bc-maxi.${cycle}.227

    # Post Files to COMOUTwmo
    cp awpaqm.${cycle}.${hr}ho3-bc.227.grib2 ${COMOUTwmo}
    cp awpaqm.${cycle}.${hr}ho3-max-bc.227.grib2 ${COMOUTwmo}

    # Distribute Data
    if [ "${SENDDBN}" = "TRUE" ]; then
      ${DBNROOT}/bin/dbn_alert ${DBNALERT_TYPE} ${NET} ${job} ${COMOUTwmo}/awpaqm.${cycle}.${hr}ho3-bc.227.grib2
      ${DBNROOT}/bin/dbn_alert ${DBNALERT_TYPE} ${NET} ${job} ${COMOUTwmo}/awpaqm.${cycle}.${hr}ho3-max-bc.227.grib2
    fi
  done
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
BIAS-CORRECTION-O3 completed successfully.

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1
