module WIPP_Flow_Derivative_module

#include "petsc/finclude/petscsys.h"
  use petscsys
  
  use PFLOTRAN_Constants_module
  use Option_module
  use WIPP_Flow_Aux_module
  use WIPP_Flow_Common_module
  use Global_Aux_module
  use Material_Aux_module
  
  implicit none

  private

  public :: WIPPFloDerivativeDriver
  
  PetscReal, parameter :: wippflo_derivative_pert_tol = 1.d-6

contains
  
! ************************************************************************** !

subroutine WIPPFloDerivativeDriver(option)
          
  use Characteristic_Curves_module
  use General_Aux_module, only : LIQUID_STATE, GAS_STATE, TWO_PHASE_STATE

  implicit none
  
  type(option_type), pointer :: option
  
  PetscInt, parameter :: ACCUMULATION = 1
  PetscInt, parameter :: INTERIOR_FLUX = 2
  PetscInt, parameter :: BOUNDARY_FLUX = 3
  PetscInt, parameter :: SRCSINK = 4
  
  PetscInt :: itype

  PetscInt :: istate
  PetscReal :: xx(3)
  PetscReal :: pert(3)
  type(wippflo_auxvar_type), pointer :: wippflo_auxvar(:)
  type(global_auxvar_type), pointer :: global_auxvar(:)
  type(material_auxvar_type), pointer :: material_auxvar(:)

  PetscInt :: istate2
  PetscReal :: xx2(3)
  PetscReal :: pert2(3)
  PetscReal :: scale2
  type(wippflo_auxvar_type), pointer :: wippflo_auxvar2(:)
  type(global_auxvar_type), pointer :: global_auxvar2(:)
  type(material_auxvar_type), pointer :: material_auxvar2(:)
  
  PetscInt :: ibndtype(3)
  PetscInt :: auxvar_mapping(WIPPFLO_MAX_INDEX)
  PetscReal :: auxvars(3) ! from aux_real_var array
  
  PetscInt :: flow_src_sink_type
  PetscReal :: qsrc(3)
  PetscReal :: srcsink_scale
  
  class(characteristic_curves_type), pointer :: characteristic_curves
  type(material_parameter_type), pointer :: material_parameter
  type(wippflo_parameter_type), pointer :: wippflo_parameter

  nullify(characteristic_curves)
  nullify(material_parameter)
  nullify(wippflo_parameter)
  call WIPPFloDerivativeSetFlowMode(option)
  call WIPPFloDerivativeSetupEOS(option)
  
  call WIPPFloDerivativeSetup(wippflo_parameter, &
                              characteristic_curves, &
                              material_parameter,option)  
  option%flow_dt = 1.d0
!  itype = ACCUMULATION
!  itype = INTERIOR_FLUX
!  itype = BOUNDARY_FLUX
  itype = SRCSINK
  
!  istate = LIQUID_STATE
!  istate = GAS_STATE
  istate = TWO_PHASE_STATE
  select case(istate)
    case(LIQUID_STATE)
      xx(1) = 1.d6
      xx(2) = 1.d-6
      xx(3) = 30.d0
!      xx(3) = 100.d0
    case(GAS_STATE)
!      xx(1) = 1.d4
!      xx(2) = 0.997d4
!      xx(3) = 15.d0
      xx(1) = 1.d6
      xx(2) = 0.997d6
      xx(3) = 30.d0
!      xx(1) = 1.d7
!      xx(2) = 0.997d7
!      xx(3) = 85.d0
    case(TWO_PHASE_STATE)
      xx(1) = 1.d6
      xx(2) = 0.5d0
      xx(3) = 30.d0
  end select

  call WIPPFloDerivativeSetupAuxVar(istate,xx,pert,wippflo_auxvar, &
                                    global_auxvar,material_auxvar, &
                                    characteristic_curves, &
                                    option)  
  
  istate2 = istate
!  istate2 = LIQUID_STATE
!  istate2 = GAS_STATE
!  istate2 = TWO_PHASE_STATE
  ! scales must range (0.001 - 1.999d0)
  scale2 = 1.d0
!  scale2 = 1.d0 - 1.d-14
!  scale2 = 1.001d0
!  scale2 = 0.999d0
!  scale2 = 100.d0
!  scale2 = 0.1d0
  select case(istate2)
    case(LIQUID_STATE)
      xx2(1) = 1.d6*scale2
      xx2(2) = 1.d-6*scale2
      xx2(3) = 30.d0*scale2
!      xx2(3) = 100.d0
    case(GAS_STATE)
!      xx2(1) = 1.d4
!      xx2(2) = 0.997d4
!      xx2(3) = 15.d0
      xx2(1) = 1.d6*scale2
      xx2(2) = 0.997d6*scale2
!      xx2(2) = 0.996d6*scale2  ! to generate gradient in air mole fraction
      xx2(3) = 30.d0*scale2
!      xx2(1) = 1.d7
!      xx2(2) = 0.997d7
!      xx2(3) = 85.d0
    case(TWO_PHASE_STATE)
      xx2(1) = 1.d6*scale2
!      xx2(1) = 1.d8
      xx2(2) = 0.5d0*scale2
      xx2(3) = 30.d0*scale2
  end select    
  
  call WIPPFloDerivativeSetupAuxVar(istate2,xx2,pert2,wippflo_auxvar2, &
                                    global_auxvar2,material_auxvar2, &
                                    characteristic_curves, &
                                    option)  
  
  call WIPPFloDerivativeAuxVar(pert,wippflo_auxvar,global_auxvar, &
                               material_auxvar,option)

  select case(itype)
    case(ACCUMULATION)
      call WIPPFloDerivativeAccum(pert,wippflo_auxvar,global_auxvar, &
                                  material_auxvar,material_parameter,option)
    case(INTERIOR_FLUX)
      call WIPPFloDerivativeAuxVar(pert2,wippflo_auxvar2,global_auxvar2, &
                                   material_auxvar2,option)
      call WIPPFloDerivativeFlux(pert,wippflo_auxvar,global_auxvar, &
                                 material_auxvar,characteristic_curves, &
                                 material_parameter,&
                                 pert2,wippflo_auxvar2,global_auxvar2, &
                                 material_auxvar2,characteristic_curves, &
                                 material_parameter, &
                                 wippflo_parameter,option)
    case(BOUNDARY_FLUX)
      ibndtype = DIRICHLET_BC     
    !  ibndtype = NEUMANN_BC
      auxvar_mapping(WIPPFLO_LIQUID_FLUX_INDEX) = 1
      auxvar_mapping(WIPPFLO_GAS_FLUX_INDEX) = 2
      auxvars(1) = -1.d-2
      auxvars(2) = -1.d-2
      ! everything downwind is XXX2, boundary is XXX
      call WIPPFloDerivativeAuxVar(pert2,wippflo_auxvar2,global_auxvar2, &
                                   material_auxvar2,option)
      call WIPPFloDerivativeFluxBC(pert2, &
                                   ibndtype,auxvar_mapping,auxvars, &
                                   wippflo_auxvar(ZERO_INTEGER), &
                                   global_auxvar(ZERO_INTEGER), &
                                   wippflo_auxvar2,global_auxvar2, &
                                   material_auxvar2, &
                                   characteristic_curves, &
                                   material_parameter, &
                                   wippflo_parameter,option)
    case(SRCSINK)
      flow_src_sink_type = VOLUMETRIC_RATE_SS
      qsrc = 0.d0
      qsrc(1) = -1.d-10
      srcsink_scale = 1.d0
      call WIPPFloDerivativeSrcSink(pert,qsrc,flow_src_sink_type, &
                                    wippflo_auxvar,global_auxvar, &
                                    material_auxvar,srcsink_scale,option)
  end select
  
  ! Destroy objects
  call WIPPFloDerivativeDestroyAuxVar(wippflo_auxvar,global_auxvar, &
                                      material_auxvar,option)  
  call WIPPFloDerivativeDestroyAuxVar(wippflo_auxvar2,global_auxvar2, &
                                      material_auxvar2,option)
  call WIPPFloDerivativeDestroy(wippflo_parameter, &
                                characteristic_curves, &
                                material_parameter,option)

end subroutine WIPPFloDerivativeDriver

! ************************************************************************** !

subroutine WIPPFloDerivativeSetup(wippflo_parameter, &
                                  characteristic_curves, &
                                  material_parameter,option)
  use Characteristic_Curves_module
  use Material_Aux_module
  use Option_module
  
  implicit none

  type(wippflo_parameter_type), pointer :: wippflo_parameter
  class(characteristic_curves_type), pointer :: characteristic_curves
  type(material_parameter_type), pointer :: material_parameter
  type(option_type), pointer :: option
  
  class(sat_func_VG_type), pointer :: sf
  class(rpf_Mualem_VG_liq_type), pointer :: rpf_liq
  class(rpf_Mualem_VG_gas_type), pointer :: rpf_gas  
  
  if (.not.associated(wippflo_parameter)) then
    allocate(wippflo_parameter)
  endif
  if (.not.associated(characteristic_curves)) then
    characteristic_curves => CharacteristicCurvesCreate()
    sf => SF_VG_Create()
    rpf_liq => RPF_Mualem_VG_Liq_Create()
    rpf_gas => RPF_Mualem_VG_Gas_Create()
    sf%m = 0.5d0
    sf%alpha = 1.d-4
    sf%Sr = 0.d0
    sf%pcmax = 1.d6
    characteristic_curves%saturation_function => sf
    rpf_liq%m = 0.5d0
    rpf_liq%Sr = 0.d0
    characteristic_curves%liq_rel_perm_function => rpf_liq
    rpf_gas%m = 0.5d0
    rpf_gas%Sr = 0.d0
    rpf_gas%Srg = 1.d-40
    characteristic_curves%gas_rel_perm_function => rpf_gas
  endif
  if (.not.associated(material_parameter)) then
    allocate(material_parameter)
    allocate(material_parameter%soil_heat_capacity(1))
    allocate(material_parameter%soil_thermal_conductivity(2,1))
    material_parameter%soil_heat_capacity(1) = 850.d0
    material_parameter%soil_thermal_conductivity(1,1) = 0.5d0
    material_parameter%soil_thermal_conductivity(2,1) = 2.d0
  endif
  
end subroutine WIPPFloDerivativeSetup

! ************************************************************************** !

subroutine WIPPFloDerivativeSetupAuxVar(istate,xx,pert,wippflo_auxvar, &
                                        global_auxvar, &
                                        material_auxvar, &
                                        characteristic_curves,option)

  use Characteristic_Curves_module
  use Option_module
  use EOS_Gas_module
  use EOS_Water_module
  
  implicit none

  PetscInt :: istate
  PetscReal :: xx(3)
  PetscReal :: pert(3)
  type(wippflo_auxvar_type), pointer :: wippflo_auxvar(:)
  type(global_auxvar_type), pointer :: global_auxvar(:)
  type(material_auxvar_type), pointer :: material_auxvar(:)
  class(characteristic_curves_type) :: characteristic_curves
  type(option_type), pointer :: option

  PetscReal :: xx_pert(3)
  PetscInt :: natural_id = 1
  PetscBool :: analytical_derivative = PETSC_TRUE
  PetscInt :: i
  
  allocate(wippflo_auxvar(0:3))
  allocate(global_auxvar(0:3))
  allocate(material_auxvar(0:3))
  
  do i = 0, 3
    call WIPPFloAuxVarInit(wippflo_auxvar(i),analytical_derivative,option)
    call GlobalAuxVarInit(global_auxvar(i),option)
    call MaterialAuxVarInit(material_auxvar(i),option)
    material_auxvar(i)%porosity_base = 0.25d0
    material_auxvar(i)%permeability = 1.d-12
    material_auxvar(i)%volume = 1.d0
    global_auxvar(i)%istate = istate
  enddo
  
  option%iflag = WIPPFLO_UPDATE_FOR_ACCUM
  call WIPPFloAuxVarCompute(xx,wippflo_auxvar(0),global_auxvar(0), &
                            material_auxvar(0),characteristic_curves, &
                            natural_id,option)  

! default perturbation approach that does not consider global or material auxvar
#if 0
  call WIPPFloAuxVarPerturb(wippflo_auxvar,global_auxvar(0), &
                            material_auxvar(0), &
                            characteristic_curves,natural_id, &
                            option)
#else
  do i = 1, 3
    option%iflag = WIPPFLO_UPDATE_FOR_DERIVATIVE
    xx_pert = xx
    pert(i) = wippflo_derivative_pert_tol * xx(i)
    xx_pert(i) = xx(i) + pert(i)
    call WIPPFloAuxVarCompute(xx_pert,wippflo_auxvar(i),global_auxvar(i), &
                              material_auxvar(i),characteristic_curves, &
                              natural_id,option)    
  enddo  
#endif

end subroutine WIPPFloDerivativeSetupAuxVar

! ************************************************************************** !

subroutine WIPPFloDerivativeSetupEOS(option)

  use Option_module
  use EOS_Gas_module
  use EOS_Water_module
  
  implicit none

  type(option_type), pointer :: option
  PetscReal :: tlow, thigh, plow, phigh
  PetscInt :: ntemp, npres  
  PetscReal :: aux(1)
  character(len=MAXWORDLENGTH) :: word
 
#if 1
  call EOSWaterSetDensity('PLANAR')
  call EOSWaterSetEnthalpy('PLANAR')
  call EOSWaterSetSteamDensity('PLANAR')
  call EOSWaterSetSteamEnthalpy('PLANAR')
#endif

  ! for ruling out density partial derivative
#if 0
  aux(1) = 996.000000000000d0
  call EOSWaterSetDensity('CONSTANT',aux)
  aux(1) = 2.27d6
  call EOSWaterSetEnthalpy('CONSTANT',aux)
#endif
#if 0
#if 1
  aux(1) = 9.899986173768605D-002
  call EOSWaterSetSteamDensity('CONSTANT',aux)  
  aux(1) = 45898000.0921749d0
  call EOSWaterSetSteamEnthalpy('CONSTANT',aux)
#endif
#if 1
!  call EOSGasSetDensityConstant(196.d0)
  call EOSGasSetDensityConstant(0.395063665868904d0)
  call EOSGasSetEnergyConstant(8841206.16464255d0)
#endif
#endif

  tlow = 1.d-1
  thigh = 350.d0
  plow = 1.d-1
  phigh = 16.d6
  ntemp = 100
  npres = 100
  word = ''
  call EOSGasTest(tlow,thigh,plow,phigh, &
                  ntemp, npres, &
                  PETSC_FALSE, PETSC_FALSE, &
                  word)  
  word = ''
  call EOSWaterTest(tlow,thigh,plow,phigh, &
                    ntemp, npres, &
                    PETSC_FALSE, PETSC_FALSE, &
                    word)  
  word = ''
  call EOSWaterSteamTest(tlow,thigh,plow,phigh, &
                         ntemp, npres, &
                         PETSC_FALSE, PETSC_FALSE, &
                         word) 
  
end subroutine WIPPFloDerivativeSetupEOS
  
! ************************************************************************** !

subroutine WIPPFloDerivativeAuxVar(pert,wippflo_auxvar,global_auxvar, &
                                   material_auxvar,option)

  use Option_module
  
  implicit none

  PetscReal :: pert(3)
  type(wippflo_auxvar_type) :: wippflo_auxvar(0:)
  type(global_auxvar_type) :: global_auxvar(0:)
  type(material_auxvar_type) :: material_auxvar(0:)
  type(option_type), pointer :: option

  PetscInt :: natural_id = 1
  PetscBool :: analytical_derivative = PETSC_TRUE
  character(len=MAXSTRINGLENGTH) :: strings(3,3)
  PetscInt :: i
  
  strings(1,1) = 'Liquid Pressure'
  strings(2,1) = 'Air Mole Fraction in Liquid'
  strings(3,1) = 'Temperature'
  strings(1,2) = 'Gas Pressure'
  strings(2,2) = 'Air Pressure'
  strings(3,2) = 'Temperature'
  strings(1,3) = 'Gas Pressure'
  strings(2,3) = 'Gas Saturation'
  strings(3,3) = 'Temperature'
  
  call WIPPFloPrintAuxVars(wippflo_auxvar(0),global_auxvar(0),material_auxvar(0), &
                           natural_id,'',option)

  do i = 1, 3
    call WIPPFloAuxVarDiff(i,wippflo_auxvar(0),global_auxvar(0), &
                           material_auxvar(0), &
                           wippflo_auxvar(i),global_auxvar(i), &
                           material_auxvar(i), &
                           pert(i), &
                           strings(i,global_auxvar(i)%istate), &
                           analytical_derivative,option) 
  enddo

end subroutine WIPPFloDerivativeAuxVar

! ************************************************************************** !

subroutine WIPPFloDerivativeAccum(pert,wippflo_auxvar,global_auxvar, &
                                  material_auxvar,material_parameter, &
                                  option)
  use Material_Aux_module
  use Option_module
  
  implicit none

  PetscReal :: pert(3)
  type(wippflo_auxvar_type) :: wippflo_auxvar(0:)
  type(global_auxvar_type) :: global_auxvar(0:)
  type(material_auxvar_type) :: material_auxvar(0:)
  type(material_parameter_type) :: material_parameter
  type(option_type), pointer :: option

  PetscInt :: natural_id = 1
  PetscInt :: i
  PetscReal, parameter :: soil_heat_capacity = 850.d0
  
  PetscInt :: irow
  PetscReal :: res(3), res_pert(3,3)
  PetscReal :: jac_anal(3,3)
  PetscReal :: jac_num(3,3)
  PetscReal :: jac_dum(3,3)  
  
  call WIPPFloPrintAuxVars(wippflo_auxvar(0),global_auxvar(0),material_auxvar(0), &
                           natural_id,'',option)

  call WIPPFloAccumulation(wippflo_auxvar(ZERO_INTEGER), &
                           global_auxvar(ZERO_INTEGER), &
                           material_auxvar(ZERO_INTEGER), &
                           material_parameter%soil_heat_capacity(1), &
                           option, &
                           res,jac_anal,PETSC_TRUE,PETSC_FALSE)

  do i = 1, 3
    call WIPPFloAccumulation(wippflo_auxvar(i), &
                             global_auxvar(i), &
                             material_auxvar(i), &
                             material_parameter%soil_heat_capacity(1), &
                             option, &
                             res_pert(:,i),jac_dum,PETSC_FALSE,PETSC_FALSE)
                           
    do irow = 1, option%nflowdof
      jac_num(irow,i) = (res_pert(irow,i)-res(irow))/pert(i)
    enddo !irow
  enddo
  
  call WIPPFloDiffJacobian('',jac_num,jac_anal,res,res_pert,pert, &
                           wippflo_derivative_pert_tol,wippflo_auxvar,option)
  
end subroutine WIPPFloDerivativeAccum

! ************************************************************************** !

subroutine WIPPFloDerivativeFlux(pert,wippflo_auxvar,global_auxvar, &
                                 material_auxvar,characteristic_curves, &
                                 material_parameter,&
                                 pert2,wippflo_auxvar2,global_auxvar2, &
                                 material_auxvar2,characteristic_curves2, &
                                 material_parameter2, &
                                 wippflo_parameter,option)

  use Option_module
  use Characteristic_Curves_module
  use Material_Aux_module
  
  implicit none

  PetscReal :: pert(3)
  type(wippflo_auxvar_type) :: wippflo_auxvar(0:)
  type(global_auxvar_type) :: global_auxvar(0:)
  type(material_auxvar_type) :: material_auxvar(0:)
  class(characteristic_curves_type) :: characteristic_curves
  type(material_parameter_type) :: material_parameter
  PetscReal :: pert2(3)
  type(wippflo_auxvar_type) :: wippflo_auxvar2(0:)
  type(global_auxvar_type) :: global_auxvar2(0:)
  type(material_auxvar_type) :: material_auxvar2(0:)
  class(characteristic_curves_type) :: characteristic_curves2
  type(material_parameter_type) :: material_parameter2
  type(wippflo_parameter_type) :: wippflo_parameter
  type(option_type), pointer :: option

  PetscInt :: natural_id = 1
  PetscInt :: i
  PetscReal, parameter :: area = 1.d0
!  PetscReal, parameter :: dist(-1:3) = [0.5d0,1.d0,1.d0,0.d0,0.d0]
!  PetscReal, parameter :: dist(-1:3) = [0.5d0,1.d0,sqrt(2.d0/2.d0),0.d0,sqrt(2.d0/2.d0)]
  PetscReal, parameter :: dist(-1:3) = [0.5d0,1.d0,0.d0,0.d0,1.d0]
  PetscInt :: upwind_direction(2)
  
  PetscReal :: v_darcy(2)
  
  
  PetscInt :: irow
  PetscReal :: res(3)
  PetscReal :: res_pert(3,3)
  PetscReal :: jac_anal(3,3)
  PetscReal :: jac_num(3,3)
  PetscReal :: jac_dum(3,3)
  
  PetscReal :: res_pert2(3,3)
  PetscReal :: jac_anal2(3,3)
  PetscReal :: jac_num2(3,3)
  PetscReal :: jac_dum2(3,3)
  
  call WIPPFloPrintAuxVars(wippflo_auxvar(0),global_auxvar(0),material_auxvar(0), &
                           natural_id,'upwind',option)
  call WIPPFloPrintAuxVars(wippflo_auxvar2(0),global_auxvar2(0),material_auxvar2(0), &
                           natural_id,'downwind',option)

  call WIPPFloFlux(wippflo_auxvar(ZERO_INTEGER), &
                   global_auxvar(ZERO_INTEGER), &
                   material_auxvar(ZERO_INTEGER), &
                   wippflo_auxvar2(ZERO_INTEGER), &
                   global_auxvar2(ZERO_INTEGER), &
                   material_auxvar2(ZERO_INTEGER), &
                   area, dist, upwind_direction, wippflo_parameter, &
                   option,v_darcy,res,jac_anal,jac_anal2, &
                   PETSC_FALSE, & ! derivative call
                   wippflo_fix_upwind_direction, &
                   PETSC_TRUE,PETSC_FALSE, &
                   PETSC_TRUE,PETSC_FALSE)                           

  do i = 1, 3
    call WIPPFloFlux(wippflo_auxvar(i), &
                     global_auxvar(i), &
                     material_auxvar(i), &
                     wippflo_auxvar2(ZERO_INTEGER), &
                     global_auxvar2(ZERO_INTEGER), &
                     material_auxvar2(ZERO_INTEGER), &
                     area, dist, upwind_direction, wippflo_parameter, &
                     option,v_darcy,res_pert(:,i),jac_dum,jac_dum2, &
                     PETSC_TRUE, & ! derivative call
                     wippflo_fix_upwind_direction, &
                     PETSC_FALSE,PETSC_FALSE, &
                     PETSC_FALSE,PETSC_FALSE)                           
    do irow = 1, option%nflowdof
      jac_num(irow,i) = (res_pert(irow,i)-res(irow))/pert(i)
    enddo !irow
  enddo
  do i = 1, 3
    call WIPPFloFlux(wippflo_auxvar(ZERO_INTEGER), &
                     global_auxvar(ZERO_INTEGER), &
                     material_auxvar(ZERO_INTEGER), &
                     wippflo_auxvar2(i), &
                     global_auxvar2(i), &
                     material_auxvar2(i), &
                     area, dist, upwind_direction, wippflo_parameter, &
                     option,v_darcy,res_pert2(:,i),jac_dum,jac_dum2, &
                     PETSC_TRUE, & ! derivative call
                     wippflo_fix_upwind_direction, &
                     PETSC_FALSE,PETSC_FALSE, &
                     PETSC_FALSE,PETSC_FALSE)                           
    do irow = 1, option%nflowdof
      jac_num2(irow,i) = (res_pert2(irow,i)-res(irow))/pert2(i)
    enddo !irow
  enddo  
  
  call WIPPFloDiffJacobian('upwind',jac_num,jac_anal,res,res_pert,pert, &
                           wippflo_derivative_pert_tol,wippflo_auxvar,option)
  write(*,*) '-----------------------------------------------------------------'
  call WIPPFloDiffJacobian('downwind',jac_num2,jac_anal2,res,res_pert2,pert2, &
                           wippflo_derivative_pert_tol,wippflo_auxvar2,option)
  
end subroutine WIPPFloDerivativeFlux

! ************************************************************************** !

subroutine WIPPFloDerivativeFluxBC(pert, &
                                   ibndtype,auxvar_mapping,auxvars, &
                                   wippflo_auxvar_bc,global_auxvar_bc, &
                                   wippflo_auxvar_dn,global_auxvar_dn, &
                                   material_auxvar_dn, &
                                   characteristic_curves_dn, &
                                   material_parameter_dn, &
                                   wippflo_parameter,option)

  use Option_module
  use Characteristic_Curves_module
  use Material_Aux_module
  
  implicit none

  type(option_type), pointer :: option
  PetscReal :: pert(3)
  PetscInt :: ibndtype(1:option%nflowdof)
  PetscInt :: auxvar_mapping(WIPPFLO_MAX_INDEX)  
  PetscReal :: auxvars(:) ! from aux_real_var array
  type(wippflo_auxvar_type) :: wippflo_auxvar_bc
  type(global_auxvar_type) :: global_auxvar_bc
  type(wippflo_auxvar_type) :: wippflo_auxvar_dn(0:)
  type(global_auxvar_type) :: global_auxvar_dn(0:)
  type(material_auxvar_type) :: material_auxvar_dn(0:)
  class(characteristic_curves_type) :: characteristic_curves_dn
  type(material_parameter_type) :: material_parameter_dn
  type(wippflo_parameter_type) :: wippflo_parameter

  PetscInt :: natural_id = 1
  PetscInt :: i
  PetscReal, parameter :: area = 1.d0
  PetscReal, parameter :: dist(-1:3) = [0.5d0,1.d0,0.d0,0.d0,1.d0]
  PetscInt :: upwind_direction(2)
  
  PetscReal :: v_darcy(2)
  
  
  PetscInt :: irow
  PetscReal :: res(3)
  PetscReal :: res_pert(3,3)
  PetscReal :: jac_anal(3,3)
  PetscReal :: jac_num(3,3)
  PetscReal :: jac_dum(3,3)
  
  call WIPPFloPrintAuxVars(wippflo_auxvar_bc,global_auxvar_bc,material_auxvar_dn(0), &
                           natural_id,'boundary',option)
  call WIPPFloPrintAuxVars(wippflo_auxvar_dn(0),global_auxvar_dn(0),material_auxvar_dn(0), &
                           natural_id,'internal',option)

  call WIPPFloBCFlux(ibndtype,auxvar_mapping,auxvars, &
                     wippflo_auxvar_bc,global_auxvar_bc, &
                     wippflo_auxvar_dn(ZERO_INTEGER),global_auxvar_dn(ZERO_INTEGER), &
                     material_auxvar_dn(ZERO_INTEGER), &
                     area,dist,upwind_direction,wippflo_parameter, &
                     option,v_darcy,res,jac_anal, &
                     PETSC_FALSE, & ! derivative call
                     wippflo_fix_upwind_direction, &
                     PETSC_TRUE, & ! update the upwind direction
                     PETSC_FALSE, & ! count upwind direction flip                     
                     PETSC_TRUE,PETSC_FALSE)                           
                           
  do i = 1, 3
    call WIPPFloBCFlux(ibndtype,auxvar_mapping,auxvars, &
                       wippflo_auxvar_bc,global_auxvar_bc, &
                       wippflo_auxvar_dn(i),global_auxvar_dn(i), &
                       material_auxvar_dn(i), &
                       area,dist,upwind_direction,wippflo_parameter, &
                       option,v_darcy,res_pert(:,i),jac_dum, &
                       PETSC_TRUE, & ! derivative call
                       wippflo_fix_upwind_direction, &
                       PETSC_FALSE, & ! update the upwind direction
                       PETSC_FALSE, & ! count upwind direction flip                       
                       PETSC_FALSE,PETSC_FALSE)                           
    do irow = 1, option%nflowdof
      jac_num(irow,i) = (res_pert(irow,i)-res(irow))/pert(i)
    enddo !irow
  enddo
  
  write(*,*) '-----------------------------------------------------------------'
  call WIPPFloDiffJacobian('boundary',jac_num,jac_anal,res,res_pert,pert, &
                           wippflo_derivative_pert_tol,wippflo_auxvar_dn,option)
  
end subroutine WIPPFloDerivativeFluxBC

! ************************************************************************** !

subroutine WIPPFloDerivativeSrcSink(pert,qsrc,flow_src_sink_type, &
                                    wippflo_auxvar,global_auxvar, &
                                    material_auxvar,scale,option)

  use Option_module
  use Characteristic_Curves_module
  use Material_Aux_module
  
  implicit none

  type(option_type), pointer :: option
  PetscReal :: pert(3)
  PetscReal :: qsrc(:)
  PetscInt :: flow_src_sink_type  
  type(wippflo_auxvar_type) :: wippflo_auxvar(0:)
  type(global_auxvar_type) :: global_auxvar(0:)
  type(material_auxvar_type) :: material_auxvar(0:)
  PetscReal :: scale
  
  PetscReal :: ss_flow_vol_flux(option%nphase)  

  PetscInt :: natural_id = 1
  PetscInt :: i
  
  PetscInt :: irow
  PetscReal :: res(3)
  PetscReal :: res_pert(3,3)
  PetscReal :: jac_anal(3,3)
  PetscReal :: jac_num(3,3)
  PetscReal :: jac_dum(3,3)
  
  call WIPPFloPrintAuxVars(wippflo_auxvar(0),global_auxvar(0),material_auxvar(0), &
                           natural_id,'srcsink',option)

  call WIPPFloSrcSink(option,qsrc,flow_src_sink_type, &
                      wippflo_auxvar(ZERO_INTEGER),global_auxvar(ZERO_INTEGER), &
                      ss_flow_vol_flux, &
                      scale,res,jac_anal,PETSC_TRUE,PETSC_FALSE)                           
                           
  do i = 1, 3
    call WIPPFloSrcSink(option,qsrc,flow_src_sink_type, &
                        wippflo_auxvar(i),global_auxvar(i), &
                        ss_flow_vol_flux, &
                        scale,res_pert(:,i),jac_dum,PETSC_FALSE,PETSC_FALSE)                           
    do irow = 1, option%nflowdof
      jac_num(irow,i) = (res_pert(irow,i)-res(irow))/pert(i)
    enddo !irow
  enddo
  
  write(*,*) '-----------------------------------------------------------------'
  call WIPPFloDiffJacobian('srcsink',jac_num,jac_anal,res,res_pert,pert, &
                           wippflo_derivative_pert_tol,wippflo_auxvar,option)
  
end subroutine WIPPFloDerivativeSrcSink

! ************************************************************************** !

subroutine WIPPFloDerivativeSetFlowMode(option)

  use Option_module

  implicit none
  
  type(option_type) :: option
  
  option%iflowmode = WF_MODE
  option%nphase = 2
  option%liquid_phase = 1  ! liquid_pressure
  option%gas_phase = 2     ! gas_pressure

  option%air_pressure_id = 3
  option%capillary_pressure_id = 4
  option%vapor_pressure_id = 5
  option%saturation_pressure_id = 6

  option%water_id = 1
  option%air_id = 2
  option%energy_id = 3

  option%nflowdof = 3
  option%nflowspec = 2
  option%use_isothermal = PETSC_FALSE
      
end subroutine WIPPFloDerivativeSetFlowMode

! ************************************************************************** !

subroutine WIPPFloDerivativeDestroyAuxVar(wippflo_auxvar,global_auxvar, &
                                          material_auxvar,option)

  use Option_module
  
  implicit none

  type(wippflo_auxvar_type), pointer :: wippflo_auxvar(:)
  type(global_auxvar_type), pointer :: global_auxvar(:)
  type(material_auxvar_type), pointer :: material_auxvar(:)
  type(option_type), pointer :: option
  
  PetscInt :: i

  do i = 0, 3
    call WIPPFloAuxVarStrip(wippflo_auxvar(i))
    call GlobalAuxVarStrip(global_auxvar(i))
    call MaterialAuxVarStrip(material_auxvar(i))
  enddo
  deallocate(wippflo_auxvar)
  deallocate(global_auxvar)
  deallocate(material_auxvar)

end subroutine WIPPFloDerivativeDestroyAuxVar

! ************************************************************************** !

subroutine WIPPFloDerivativeDestroy(wippflo_parameter, &
                                  characteristic_curves, &
                                  material_parameter,option)
  use WIPP_Flow_Aux_module
  use Characteristic_Curves_module
  use Material_Aux_module
  use Option_module
  
  implicit none

  type(wippflo_parameter_type), pointer :: wippflo_parameter
  class(characteristic_curves_type), pointer :: characteristic_curves
  type(material_parameter_type), pointer :: material_parameter
  type(option_type), pointer :: option
  
  if (associated(wippflo_parameter)) then
    deallocate(wippflo_parameter)
    nullify(wippflo_parameter)
  endif
  call CharacteristicCurvesDestroy(characteristic_curves)
  if (associated(material_parameter)) then
    if (associated(material_parameter%soil_heat_capacity)) &
      deallocate(material_parameter%soil_heat_capacity)
    nullify(material_parameter%soil_heat_capacity)
    if (associated(material_parameter%soil_thermal_conductivity)) &
      deallocate(material_parameter%soil_thermal_conductivity)
    nullify(material_parameter%soil_thermal_conductivity)
    deallocate(material_parameter)
    nullify(material_parameter)    
  endif

end subroutine WIPPFloDerivativeDestroy

end module WIPP_Flow_Derivative_module
