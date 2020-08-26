#!/bin/bash -l

shopt -s expand_aliases

### Patches
# to create a patch...
if [ "1" -eq "0" ]; then
  CESMROOT=~/work/cesm-dev/
  filename="advance_clubb_core_module"
  SUBPATH="components/cam/src/physics/clubb/"
  CESMCOMPONENT="cam"
  SOURCEMODDIR=~/ideal-mods/CLUBB/20200819_taudiags/SourceDiffs/src.${CESMCOMPONENT}/
  mkdir -p ${SOURCEMODDIR}
  diff -b -U 3 ${CESMROOT}/${SUBPATH}/${filename}.F90 ~/TC_PBL/RCE.QPC6.ne0np4tcfplane.ne15x8.exp294.001/SourceMods/src.${CESMCOMPONENT}/${filename}.F90 > ${SOURCEMODDIR}/${filename}.patch
fi

function patch_code {
  local PATCHFLAGS=" "
  local PATCHDIR=${1}
  local filename=${2}
  local SUBPATH=${3}
  local CESMCOMPONENT=${4}
  echo "Patching ${filename}.F90... using patch file from ${PATCHDIR}"
  cp ${CESMROOT}/${SUBPATH}/${filename}.F90 ./SourceMods/src.${CESMCOMPONENT}/
  patch ${PATCHFLAGS} ./SourceMods/src.${CESMCOMPONENT}/${filename}.F90 < ${PATCHDIR}/src.${CESMCOMPONENT}/${filename}.patch
  echo "----------------------------"
}

DTIME=450.0
RES="ne15x8"
PHYS="QPC6"  # QPC5 or QPC6
EXPID="exp292"
ENS="001"
NLEV=56
NDAYS=10
## CAM6 settings
PREDICT_UPWP=true
DIAG_LSCALE_FROM_TAU=true
INVRS_TAU_BKGND=4.0
INVRS_TAU_SFC=0.3
INVRS_TAU_SHEAR=0.018
INVRS_TAU_N2=0.15
CK10=9999.9
## CAM5 settings
CAM5_DO_MG2=true
## General settings
LY09=true             # Do LY09?
CD_CAP_MS=31.0        # negative means no changes

if [[ $(hostname -s) = cheyenne* ]]; then
  IDEALDIR=/glade/u/home/zarzycki/ideal-mods/
  NUMNODES=16
  WALLTIME="03:28:00"
  RUNQUEUE="premium"
  PROJID=UPSU0032
  CESMROOT=/glade/u/home/zarzycki/work/cesm-dev/
  GRIDSDIR=~/work/grids/
  INICDIR=~/work/initial/tc_testcase/
  CSMDATA=/glade/p/cesmdata/cseg/inputdata/
  RCEINPUTDATA=/glade/u/home/kareed/RCE_inputdata/
  CASEDIR=~/TC_PBL/
  MACHNAME="cheyenne"
  EXTRASETUPFLAGS=""
  EXTRASUBFLAGS=""
  USENODEBUILD=true
elif [[ $(hostname -s) = aci-* ]]; then
  source /usr/share/lmod/lmod/init/bash
  module purge
  module use /gpfs/group/dml129/default/sw/modules
  module load intel/16.0.3
  module load impi/5.1.3
  module load netcdf/4.3.3.1-intel-16.0.3
  module load python/2.7.14-anaconda5.0.1
  module load perl/5.24.1
  module list
  IDEALDIR=/storage/home/cmz5202/ideal-models/
  NUMNODES=15
  WALLTIME="03:58:00"
  RUNQUEUE="batch"
  PROJID="cmz5202_a_g_sc_default"
  CESMROOT=/storage/home/cmz5202/cesm-dev/
  GRIDSDIR=/storage/work/cmz5202/grids/
  INICDIR=/storage/work/${LOGNAME}/inic/
  CSMDATA=/gpfs/group/dml129/default/sw/cesm/cesm-inputdata/
  RCEINPUTDATA=NULL
  CASEDIR=~/TC_PBL/
  MACHNAME="ACI"
  EXTRASETUPFLAGS="--compiler intel"
  EXTRASUBFLAGS='--batch-args "-N CESM"'
  USENODEBUILD=false
fi


CASENAME=RCE.${PHYS}.ne0np4tcfplane.${RES}.${EXPID}.${ENS}

# Do math for settings...
if [ ${RES} == 'ne15x8' ] ; then
  STABILITY=225.0
elif [ ${RES} == 'ne15x16' ]; then
  #STABILITY=112.5
  STABILITY=90.0
else
  echo "Unsupported res "${RES}
  exit
fi
ATM_NCPL=`python3 -c "print(int(86400/${DTIME}))"`
SE_NSPLIT=`python3 -c "from math import ceil; print(int(ceil(${DTIME}/${STABILITY})))"`

mkdir -p ${CASEDIR}
rm -rf ${CASEDIR}/${CASENAME}

cd ${CESMROOT}/cime/scripts
./create_newcase --case ${CASEDIR}/${CASENAME} --res ne0TCFPLANE${RES}_ne0TCFPLANE${RES}_mt12 --compset ${PHYS} --mach ${MACHNAME} ${EXTRASETUPFLAGS} --run-unsupported

cd ${CASEDIR}/${CASENAME}

PATCHDIR=${IDEALDIR}/RCE/SourceDiffs/
#patch_code ${PATCHDIR} "orbit" "components/cam/src/utils/" "cam"
#patch_code ${PATCHDIR} "physconst" "components/cam/src/utils/" "cam"
#patch_code ${PATCHDIR} "radiation" "components/cam/src/physics/rrtmg/" "cam"
patch_code ${PATCHDIR} "cube_mod" "components/cam/src/dynamics/se/dycore/" "cam"
#patch_code ${PATCHDIR} "docn_comp_mod" "cime/src/components/data_comps/docn/mct/" "docn"

if [ "${LY09}" = true ] ; then
  echo "Using Large and Yeager Cd modifications"
  patch_code ${PATCHDIR} "shr_flux_mod" "cime/src/share/util/" "share"
  if (( $(echo "$CD_CAP_MS > 0" | bc -l) )); then
    echo "Adjusting Cd"
    cd ./SourceMods/src.share/
      sed -i -e 's/33.0000/'${CD_CAP_MS}'/g' shr_flux_mod.F90
    cd ${CASEDIR}/${CASENAME}
  fi
fi

## CMZ: min wind now controlled by  seq_flux_atmocn_minwind = 1.0D0
if [ ${PHYS} == 'QPC6' ] ; then
  PATCHDIR=${IDEALDIR}/CLUBB/20200819_taudiags/SourceDiffs/
  patch_code ${PATCHDIR} "advance_clubb_core_module" "components/cam/src/physics/clubb/" "cam"
  patch_code ${PATCHDIR} "stats_variables" "components/cam/src/physics/clubb/" "cam"
  patch_code ${PATCHDIR} "stats_zm_module" "components/cam/src/physics/clubb/" "cam"
  #cp /glade/u/home/zarzycki/ideal-mods/CLUBB/tau-sculpt/vince-modif/*F90 ./SourceMods/src.cam/
  cd ./SourceMods/src.cam/
  
  if [ "${DIAG_LSCALE_FROM_TAU}" = true ] ; then
    # Copy parameters_tunable and sed in updated tau values
    cp ${CESMROOT}/components/cam/src/physics/clubb/parameters_tunable.F90 .
    sed -i -e 's/^\s*C_invrs_tau_bkgnd\s*=\s*[0-9].*/    C_invrs_tau_bkgnd = '${INVRS_TAU_BKGND}'_core_rknd, \& !/g' parameters_tunable.F90
    sed -i -e 's/^\s* C_invrs_tau_sfc\s*=\s*[0-9].*/    C_invrs_tau_sfc = '${INVRS_TAU_SFC}'_core_rknd, \& !/g' parameters_tunable.F90
    sed -i -e 's/^\s* C_invrs_tau_shear\s*=\s*[0-9].*/    C_invrs_tau_shear = '${INVRS_TAU_SHEAR}'_core_rknd, \& !/g' parameters_tunable.F90
    sed -i -e 's/^\s* C_invrs_tau_N2\s*=\s*[0-9].*/    C_invrs_tau_N2 = '${INVRS_TAU_N2}'_core_rknd, \& !/g' parameters_tunable.F90
    CK10=9999.9
  fi
  cd ${CASEDIR}/${CASENAME}
fi

./xmlchange CPL_ALBAV=TRUE

./xmlchange STOP_N=${NDAYS}
./xmlchange DOUT_S=FALSE
./xmlchange --append CAM_CONFIG_OPTS="-nlev ${NLEV}"

./xmlchange EPS_AAREA=1.0e-03
./xmlchange ATM_NCPL=${ATM_NCPL}
./xmlchange REST_N=9999
./xmlchange REST_OPTION=nyears

./xmlchange NTASKS=-${NUMNODES}
./xmlchange NTASKS_ESP=1
./xmlchange NTASKS_IAC=1

./xmlchange JOB_WALLCLOCK_TIME=${WALLTIME}
./xmlchange PROJECT=${PROJID}
./xmlchange JOB_QUEUE=${RUNQUEUE}

if [ ${PHYS} == 'QPC5' ] ; then
  echo "USING CAM5 PHYSICS"
  # Turn off active chem and use MG2
  ./xmlchange --append CAM_CONFIG_OPTS="-chem none"
  if [ "${CAM5_DO_MG2}" = true ] ; then
    echo "-- MG2"
    ./xmlchange --append CAM_CONFIG_OPTS="-microphys mg2"
  else
    echo "-- MG1"
  fi
  # Add CAM5 specific output vars
  EXTRAVARS="'UW_leng', 'UW_tke', 'tkeavg_Cu', 'UW_kvm', 'UW_smcl'"
  DIAGOUT=","$EXTRAVARS
elif [ ${PHYS} == 'QPC6' ]; then
  # Change to Kevin's RCE use case
  ./xmlchange CAM_NML_USE_CASE="aquaplanet_rce_cam6"
   # Add CAM6 specific output vars
  EXTRAVARS="'Lscale','em','Kh_zm','invrs_tau_bkgnd','invrs_tau_sfc','invrs_tau_shear','bv_freq_sqd','Richardson_num','tau_zm'"
  DIAGOUT=","$EXTRAVARS
else
  DIAGOUT=""
fi

# Specify constant SSTs
./xmlchange DOCN_MODE="sst_aquap_constant"
./xmlchange DOCN_AQPCONST_VALUE="302.15"

############### BEGIN USER_NL_CAM ###############################################

cat > user_nl_cam <<EOF

nhtfrq=0,-6,-1,-24
fincl2='PS','U','V','OMEGA','T','Q','CLDLIQ','CLDICE','Z3'
fincl3='PRECL','PRECC','PRECT','TMQ','FLUT'
fincl4='PS','SST','QBOT','TBOT','UBOT','VBOT','PTTEND','DTCOND','RELHUM','CME','SL','MPDT','MPDQ','TAUX','TAUY','U10','SHFLX','LHFLX','TTEND_TOT','DTV','DUV','DVV','KVH','KVT','PBLH','USTAR'${DIAGOUT}
mfilt=1,4,24,1
avgflag_pertape='A','I','I','I'

se_mesh_file='${GRIDSDIR}/exodus/ne0np4tcfplane.${RES}.g'
bnd_topo='${INICDIR}/ne0np4tcplane${RES}_INIC_L${NLEV}.${ENS}.nc'
ncdata='${INICDIR}/ne0np4tcplane${RES}_INIC_L${NLEV}.${ENS}.nc'

drydep_srf_file='${CSMDATA}/atm/cam/chem/trop_mam/atmsrf_ne120np4_110920.nc'
se_nsplit=${SE_NSPLIT}
se_rsplit=3
se_hypervis_subcycle=4
se_ne=0
se_ftype=0
se_nu=1.0000e13
se_nu_div=2.5000e13
se_nu_p = 1.00e13
se_nu_top = 2.0e5
se_fine_ne=120
se_hypervis_power=3.322
se_max_hypervis_courant=1.9

EOF

if [ ${PHYS} == 'QPC5' ] ; then
  cat >> user_nl_cam <<EOF
ch4vmr = 1.650e-6
co2vmr = 348.0e-6
f11vmr = 0.0
f12vmr = 0.0
n2ovmr = 0.306e-6
prescribed_ozone_datapath              = '${RCEINPUTDATA}'
prescribed_ozone_file          = 'RCEMIPozone.nc'
solar_irrad_data_file   = '${RCEINPUTDATA}/ape_solar_ave_tsi_551.58.nc'
prescribed_ozone_datapath              = '${RCEINPUTDATA}'
prescribed_ozone_file          = 'RCEozone.nc'
prescribed_aero_datapath='${RCEINPUTDATA}'
prescribed_aero_file='aero_zero.nc'
prescribed_aero_cycle_yr=2000
prescribed_aero_type='CYCLICAL'
prescribed_aero_model='bulk'
EOF
elif [ ${PHYS} == 'QPC6' ]; then
  cat >> user_nl_cam <<EOF
clubb_c_k10=${CK10}
clubb_timestep=112.5
cld_macmic_num_steps=1
clubb_l_predict_upwp_vpwp = .${PREDICT_UPWP}.
clubb_l_diag_lscale_from_tau = .${DIAG_LSCALE_FROM_TAU}.
clubb_history=.true.
clubb_vars_zt = 'thlm', 'thvm', 'rtm', 'rcm', 'rvm', 'um', 'vm', 'um_ref','vm_ref','ug', 'vg', 'cloud_frac', 'cloud_cover', 'rcm_in_layer', 'rcm_in_cloud', 'p_in_Pa', 'exner', 'rho_ds_zt', 'thv_ds_zt', 'Lscale', 'Lscale_pert_1', 'Lscale_pert_2', 'T_in_K', 'rel_humidity', 'wp3', 'wpthlp2', 'wp2thlp', 'wprtp2', 'wp2rtp', 'Lscale_up', 'Lscale_down', 'tau_zt', 'Kh_zt', 'wp2thvp', 'wp2rcp', 'wprtpthlp', 'sigma_sqd_w_zt', 'rho', 'radht', 'radht_LW', 'radht_SW', 'Ncm', 'Nc_in_cloud', 'Nc_activated', 'snowslope', 'sed_rcm', 'rsat', 'rsati', 'diam', 'mass_ice_cryst', 'rcm_icedfs', 'u_T_cm', 'rtm_bt', 'rtm_ma', 'rtm_ta', 'rtm_mfl', 'rtm_tacl', 'rtm_cl', 'rtm_forcing', 'rtm_sdmp','rtm_mc', 'rtm_pd', 'rvm_mc', 'rcm_mc', 'rcm_sd_mg_morr', 'thlm_bt', 'thlm_ma', 'thlm_ta', 'thlm_mfl', 'thlm_tacl', 'thlm_cl', 'thlm_forcing', 'thlm_sdmp','thlm_mc', 'thlm_old', 'thlm_without_ta', 'thlm_mfl_min', 'thlm_mfl_max', 'thlm_enter_mfl', 'thlm_exit_mfl', 'rtm_old', 'rtm_without_ta', 'rtm_mfl_min', 'rtm_mfl_max', 'rtm_enter_mfl', 'rtm_exit_mfl', 'um_bt', 'um_ma', 'um_gf', 'um_cf', 'um_ta', 'um_f', 'um_sdmp', 'um_ndg', 'vm_bt', 'vm_ma', 'vm_gf', 'vm_cf', 'vm_ta', 'vm_f', 'vm_sdmp', 'vm_ndg', 'wp3_bt', 'wp3_ma', 'wp3_ta', 'wp3_tp', 'wp3_ac', 'wp3_bp1', 'wp3_bp2', 'wp3_pr1', 'wp3_pr2', 'wp3_dp1', 'wp3_cl', 'mixt_frac', 'w_1', 'w_2', 'varnce_w_1', 'varnce_w_2', 'thl_1', 'thl_2', 'varnce_thl_1', 'varnce_thl_2', 'rt_1', 'rt_2', 'varnce_rt_1', 'varnce_rt_2', 'rc_1', 'rc_2', 'rsatl_1', 'rsatl_2', 'cloud_frac_1', 'cloud_frac_2', 'a3_coef_zt', 'wp3_on_wp2_zt', 'chi_1', 'chi_2', 'stdev_chi_1', 'stdev_chi_2', 'stdev_eta_1', 'stdev_eta_2', 'covar_chi_eta_1', 'covar_chi_eta_2', 'corr_chi_eta_1', 'corr_chi_eta_2', 'corr_rt_thl_1', 'crt_1', 'crt_2', 'cthl_1', 'cthl_2', 'precip_frac', 'precip_frac_1', 'precip_frac_2', 'Ncnm', 'wp2_zt', 'thlp2_zt', 'wpthlp_zt', 'wprtp_zt', 'rtp2_zt', 'rtpthlp_zt', 'up2_zt', 'vp2_zt', 'upwp_zt', 'vpwp_zt', 'C11_Skw_fnc'
clubb_vars_zm = 'wp2', 'rtp2', 'thlp2', 'rtpthlp', 'wprtp', 'wpthlp', 'wp4', 'up2', 'vp2', 'wpthvp', 'rtpthvp', 'thlpthvp', 'tau_zm', 'Kh_zm', 'wprcp', 'wm_zm', 'thlprcp', 'rtprcp', 'rcp2', 'upwp', 'vpwp', 'rho_zm', 'sigma_sqd_w', 'Skw_velocity', 'gamma_Skw_fnc', 'C6rt_Skw_fnc', 'C6thl_Skw_fnc', 'C7_Skw_fnc', 'C1_Skw_fnc', 'a3_coef', 'wp3_on_wp2', 'rcm_zm', 'rtm_zm', 'thlm_zm', 'cloud_frac_zm', 'rho_ds_zm', 'thv_ds_zm', 'em', 'mean_w_up', 'mean_w_down', 'shear', 'wp3_zm', 'Frad', 'Frad_LW', 'Frad_SW', 'Frad_LW_up', 'Frad_SW_up', 'Frad_LW_down', 'Frad_SW_down', 'Fprec', 'Fcsed', 'wp2_bt', 'wp2_ma', 'wp2_ta', 'wp2_ac', 'wp2_bp', 'wp2_pr1', 'wp2_pr2', 'wp2_pr3', 'wp2_dp1', 'wp2_dp2', 'wp2_cl', 'wp2_pd', 'wp2_sf', 'vp2_bt', 'vp2_ma', 'vp2_ta', 'vp2_tp', 'vp2_dp1', 'vp2_dp2', 'vp2_pr1', 'vp2_pr2', 'vp2_cl', 'vp2_pd', 'vp2_sf', 'up2_bt', 'up2_ma', 'up2_ta', 'up2_tp', 'up2_dp1', 'up2_dp2', 'up2_pr1', 'up2_pr2', 'up2_cl', 'up2_pd', 'up2_sf', 'wprtp_bt', 'wprtp_ma', 'wprtp_ta', 'wprtp_tp', 'wprtp_ac', 'wprtp_bp', 'wprtp_pr1', 'wprtp_pr2', 'wprtp_pr3', 'wprtp_dp1', 'wprtp_mfl', 'wprtp_cl', 'wprtp_sicl', 'wprtp_pd', 'wprtp_forcing', 'wprtp_mc', 'wpthlp_bt', 'wpthlp_ma', 'wpthlp_ta', 'wpthlp_tp', 'wpthlp_ac', 'wpthlp_bp', 'wpthlp_pr1', 'wpthlp_pr2', 'wpthlp_pr3', 'wpthlp_dp1', 'wpthlp_mfl', 'wpthlp_cl', 'wpthlp_sicl', 'wpthlp_forcing', 'wpthlp_mc', 'rtp2_bt', 'rtp2_ma', 'rtp2_ta', 'rtp2_tp', 'rtp2_dp1', 'rtp2_dp2', 'rtp2_cl', 'rtp2_pd', 'rtp2_sf', 'rtp2_forcing', 'rtp2_mc', 'thlp2_bt', 'thlp2_ma', 'thlp2_ta', 'thlp2_tp', 'thlp2_dp1', 'thlp2_dp2', 'thlp2_cl', 'thlp2_pd', 'thlp2_sf', 'thlp2_forcing', 'thlp2_mc', 'rtpthlp_bt', 'rtpthlp_ma', 'rtpthlp_ta', 'rtpthlp_tp1', 'rtpthlp_tp2', 'rtpthlp_dp1', 'rtpthlp_dp2', 'rtpthlp_cl', 'rtpthlp_sf', 'rtpthlp_forcing', 'rtpthlp_mc', 'wpthlp_entermfl', 'wpthlp_exit_mfl', 'wprtp_enter_mfl', 'wprtp_exit_mfl', 'wpthlp_mfl_min', 'wpthlp_mfl_max', 'wprtp_mfl_min', 'wprtp_mfl_max', 'Richardson_num', 'shear_sqd','invrs_tau_bkgnd','invrs_tau_sfc','invrs_tau_shear','bv_freq_sqd'
EOF
else
  echo "nothing"
fi

############### END USER_NL_CAM ###############################################

echo "Done with config!"

./case.setup

echo "Done with setup!"

if [ "${USENODEBUILD}" = true ] ; then
  cesm.build --skip-provenance-check
else
  ./case.build --skip-provenance-check
fi

echo "Done with build!"
./case.submit --batch-args "-N TC.${EXPID}.${ENS}"