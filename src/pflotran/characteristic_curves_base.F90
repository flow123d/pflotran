module Characteristic_Curves_Base_module

#include "petsc/finclude/petscsys.h"
  use petscsys
  use PFLOTRAN_Constants_module

  implicit none

  private

  PetscReal, parameter, public :: DEFAULT_PCMAX = 1.d9

  type, public :: polynomial_type
    PetscReal :: low
    PetscReal :: high
    PetscReal :: coefficients(4)
  end type polynomial_type

!-----------------------------------------------------------------------------
!-- Saturation Functions -----------------------------------------------------
!-----------------------------------------------------------------------------
  type, public :: sat_func_base_type
    type(polynomial_type), pointer :: sat_poly
    type(polynomial_type), pointer :: pres_poly
    PetscReal :: Sr
    PetscReal :: pcmax
    PetscBool :: analytical_derivative_available
    PetscBool :: calc_int_tension
    PetscBool :: calc_vapor_pressure
  contains
    procedure, public :: Init => SFBaseInit
    procedure, public :: Verify => SFBaseVerify
    procedure, public :: Test => SFBaseTest
    procedure, public :: SetupPolynomials => SFBaseSetupPolynomials
    procedure, public :: CapillaryPressure => SFBaseCapillaryPressure
    procedure, public :: Saturation => SFBaseSaturation
    procedure, public :: EffectiveSaturation => SFBaseEffectiveSaturation
    procedure, public :: D2SatDP2 => SFBaseD2SatDP2
!    procedure, public :: CalcInterfacialTension => SFBaseSurfaceTension
    procedure, public :: GetResidualSaturation => SFBaseGetResidualSaturation
    procedure, public :: GetAlpha_ => SFBaseGetNeedsToBeExtended
    procedure, public :: GetM_ => SFBaseGetNeedsToBeExtended
    procedure, public :: SetResidualSaturation => SFBaseSetResidualSaturation
    procedure, public :: SetAlpha_ => SFBaseSetNeedsToBeExtended
    procedure, public :: SetM_ => SFBaseSetNeedsToBeExtended
  end type sat_func_base_type

!-----------------------------------------------------------------------------
!-- Relative Permeability Functions ------------------------------------------
!-----------------------------------------------------------------------------
  type, public :: rel_perm_func_base_type
    type(polynomial_type), pointer :: poly
    PetscReal :: Sr
    PetscReal :: Srg
    PetscBool :: analytical_derivative_available
  contains
    procedure, public :: Init => RPFBaseInit
    procedure, public :: Verify => RPFBaseVerify
    procedure, public :: Test => RPFBaseTest
    procedure, public :: SetupPolynomials => RPFBaseSetupPolynomials
    procedure, public :: RelativePermeability => RPFBaseRelPerm
    procedure, public :: EffectiveSaturation => &
                           RPFBaseLiqEffectiveSaturation
    procedure, public :: EffectiveGasSaturation => &
                           RPFBaseGasEffectiveSaturation
    procedure, public :: GetResidualSaturation => RPFBaseGetResidualSaturation
    procedure, public :: GetM_ => RPFBaseGetNeedsToBeExtended
    procedure, public :: SetResidualSaturation => RPFBaseSetResidualSaturation
    procedure, public :: SetM_ => RPFBaseSetNeedsToBeExtended
  end type rel_perm_func_base_type

  public :: PolynomialCreate, &
            PolynomialDestroy, &
            SFBaseInit, &
            SFBaseVerify, &
            SFBaseTest, &
            SFBaseCapillaryPressure, &
            SFBaseSaturation, &
            RPFBaseInit, &
            RPFBaseVerify, &
            RPFBaseTest, &
            RPFBaseRelPerm, &
            SaturationFunctionDestroy, &
            PermeabilityFunctionDestroy

contains

! ************************************************************************** !

function PolynomialCreate()

  implicit none

  type(polynomial_type), pointer :: PolynomialCreate

  allocate(PolynomialCreate)
  PolynomialCreate%low = 0.d0
  PolynomialCreate%high = 0.d0
  PolynomialCreate%coefficients(:) = 0.d0

end function PolynomialCreate

! ************************************************************************** !
! ************************************************************************** !

subroutine SFBaseInit(this)

  implicit none

  class(sat_func_base_type) :: this

  ! Cannot allocate here.  Allocation takes place in daughter class
  nullify(this%sat_poly)
  nullify(this%pres_poly)
  this%Sr = UNINITIALIZED_DOUBLE
  this%pcmax = DEFAULT_PCMAX
  this%analytical_derivative_available = PETSC_FALSE
  this%calc_int_tension = PETSC_FALSE
  this%calc_vapor_pressure = PETSC_FALSE

end subroutine SFBaseInit

! ************************************************************************** !

subroutine SFBaseVerify(this,name,option)

  use Option_module

  implicit none

  class(sat_func_base_type) :: this
  character(len=MAXSTRINGLENGTH) :: name
  type(option_type) :: option

  if (Uninitialized(this%Sr)) then
    option%io_buffer = UninitializedMessage('LIQUID_RESIDUAL_SATURATION', &
                                            name)
    call PrintErrMsg(option)
  endif

  if ((.not.this%analytical_derivative_available) .and. &
      (.not.option%flow%numerical_derivatives)) then
    option%io_buffer = 'Analytical derivatives are not available for the &
      &capillary pressure - saturation function chosen: ' // &
      trim(name)
    call PrintErrMsg(option)
  endif

end subroutine SFBaseVerify

! ************************************************************************** !

subroutine RPFBaseInit(this)

  implicit none

  class(rel_perm_func_base_type) :: this

  ! Cannot allocate here.  Allocation takes place in daughter class
  nullify(this%poly)
  this%Sr = UNINITIALIZED_DOUBLE
  this%Srg = UNINITIALIZED_DOUBLE
  this%analytical_derivative_available = PETSC_FALSE

end subroutine RPFBaseInit

! ************************************************************************** !

subroutine RPFBaseVerify(this,name,option)

  use Option_module

  implicit none

  class(rel_perm_func_base_type) :: this
  character(len=MAXSTRINGLENGTH) :: name
  type(option_type) :: option

  if (Uninitialized(this%Sr)) then
    option%io_buffer = UninitializedMessage('LIQUID_RESIDUAL_SATURATION', &
                                            name)
    call PrintErrMsg(option)
  endif

  if ((.not.this%analytical_derivative_available) .and. &
      (.not.option%flow%numerical_derivatives)) then
    option%io_buffer = 'Analytical derivatives are not available for the &
      &relative permeability function chosen: ' // trim(name)
    call PrintErrMsg(option)
  endif

end subroutine RPFBaseVerify

! ************************************************************************** !

subroutine SFBaseSetupPolynomials(this,option,error_string)

  ! Sets up polynomials for smoothing saturation functions

  use Option_module

  implicit none

  class(sat_func_base_type) :: this
  type(option_type) :: option
  character(len=MAXSTRINGLENGTH) :: error_string

  option%io_buffer = 'SF Smoothing not supported for ' // trim(error_string)
  call PrintErrMsg(option)

end subroutine SFBaseSetupPolynomials

! ************************************************************************** !

subroutine RPFBaseSetupPolynomials(this,option,error_string)

  ! Sets up polynomials for smoothing relative permeability functions

  use Option_module

  implicit none

  class(rel_perm_func_base_type) :: this
  type(option_type) :: option
  character(len=MAXSTRINGLENGTH) :: error_string

  option%io_buffer = 'RPF Smoothing not supported for ' // trim(error_string)
  call PrintErrMsg(option)

end subroutine RPFBaseSetupPolynomials

! ************************************************************************** !

subroutine SFBaseCapillaryPressure(this,liquid_saturation, &
                                   capillary_pressure,dpc_dsatl,option)
  use Option_module

  implicit none

  class(sat_func_base_type) :: this
  PetscReal, intent(in) :: liquid_saturation
  PetscReal, intent(out) :: capillary_pressure
  PetscReal, intent(out) :: dpc_dsatl
  type(option_type), intent(inout) :: option

  option%io_buffer = 'SFBaseCapillaryPressure must be extended.'
  call PrintErrMsg(option)

end subroutine SFBaseCapillaryPressure

! ************************************************************************** !

subroutine SFBaseSaturation(this,capillary_pressure, &
                            liquid_saturation,dsat_dpres,option)
  use Option_module

  implicit none

  class(sat_func_base_type) :: this
  PetscReal, intent(in) :: capillary_pressure
  PetscReal, intent(out) :: liquid_saturation
  PetscReal, intent(out) :: dsat_dpres
  type(option_type), intent(inout) :: option

  option%io_buffer = 'SFBaseSaturation must be extended.'
  call PrintErrMsg(option)

end subroutine SFBaseSaturation

! ************************************************************************** !

function SFBaseGetResidualSaturation(this)

  implicit none

  class(sat_func_base_type) :: this

  PetscReal :: SFBaseGetResidualSaturation

  SFBaseGetResidualSaturation = this%Sr

end function SFBaseGetResidualSaturation

! ************************************************************************** !

function SFBaseGetNeedsToBeExtended(this)

  implicit none

  class(sat_func_base_type) :: this

  PetscReal :: SFBaseGetNeedsToBeExtended

  SFBaseGetNeedsToBeExtended = UNINITIALIZED_DOUBLE
  print *, 'A SFBaseGetXXX routine needs to be extended'
  stop

end function SFBaseGetNeedsToBeExtended

! ************************************************************************** !

subroutine SFBaseSetResidualSaturation(this,tempreal)

  implicit none

  class(sat_func_base_type) :: this
  PetscReal :: tempreal

  this%Sr = tempreal

end subroutine SFBaseSetResidualSaturation

! ************************************************************************** !

subroutine SFBaseSetNeedsToBeExtended(this,tempreal)

  implicit none

  class(sat_func_base_type) :: this
  PetscReal :: tempreal

  print *, 'A SFBaseSetXXX routine needs to be extended'
  stop

end subroutine SFBaseSetNeedsToBeExtended

! ************************************************************************** !

subroutine SFBaseEffectiveSaturation(this,liquid_saturation, &
                                     effective_saturation,deffsat_dsat, &
                                     option)
  use Option_module

  implicit none

  class(sat_func_base_type) :: this
  PetscReal, intent(in) :: liquid_saturation
  PetscReal, intent(out) :: effective_saturation
  PetscReal, intent(out) :: deffsat_dsat
  type(option_type), intent(inout) :: option

  deffsat_dsat = 1.d0 / (1.d0 - this%Sr)
  effective_saturation = (liquid_saturation - this%Sr) * deffsat_dsat

end subroutine SFBaseEffectiveSaturation

! ************************************************************************** !

subroutine SFBaseD2SatDP2(this,pc,d2s_dp2,option)

  use Option_module

  implicit none

  class(sat_func_base_type) :: this
  PetscReal, intent(in) :: pc
  PetscReal, intent(out) :: d2s_dp2
  type(option_type), intent(inout) :: option

  option%io_buffer = 'SFBaseD2SatDP2 must be extended.'
  call PrintErrMsg(option)

end subroutine SFBaseD2SatDP2

! ************************************************************************** !

subroutine SFBaseTest(this,cc_name,option)

  use Option_module
  use Material_Aux_module

  implicit none

  class(sat_func_base_type) :: this
  character(len=MAXWORDLENGTH) :: cc_name
  type(option_type), intent(inout) :: option

  character(len=MAXSTRINGLENGTH) :: string
  PetscInt, parameter :: num_values = 101
  PetscReal :: pc, pc_increment
  PetscReal :: capillary_pressure(num_values)
  PetscReal :: liquid_saturation(num_values)
  PetscReal :: dpc_dsatl(num_values)
  PetscReal :: dpc_dsatl_numerical(num_values)
  PetscReal :: dsat_dpres(num_values)
  PetscReal :: dsat_dpres_numerical(num_values)
  PetscReal :: capillary_pressure_pert
  PetscReal :: liquid_saturation_pert
  PetscReal :: perturbation
  PetscReal :: pert
  PetscReal :: dummy_real
  PetscInt :: count, i

  ! calculate saturation as a function of capillary pressure
  ! start at 1 Pa up to maximum capillary pressure
  pc = 1.d0
  pc_increment = 1.d0
  perturbation = 1.d-6
  count = 0
  do
    if (pc > this%pcmax) exit
    count = count + 1
    call this%Saturation(pc,liquid_saturation(count),dsat_dpres(count),option)
    capillary_pressure(count) = pc
    ! calculate numerical derivative dsat_dpres_numerical
    capillary_pressure_pert = pc + pc*perturbation
    call this%Saturation(capillary_pressure_pert,liquid_saturation_pert, &
                         dummy_real,option)
    dsat_dpres_numerical(count) = (liquid_saturation_pert - &
         & liquid_saturation(count))/(pc*perturbation)*(-1.d0) ! dPc/dPres
    ! get next value for pc
    if (pc > 0.99d0*pc_increment*10.d0) pc_increment = pc_increment*10.d0
    pc = pc + pc_increment
  enddo

  write(string,*) cc_name
  string = trim(cc_name) // '_sat_from_pc.dat'
  open(unit=86,file=string)
  write(86,*) '"capillary pressure", "saturation", "dsat/dpres", &
              &"dsat/dpres_numerical"'
  do i = 1, count
    write(86,'(4es14.6)') capillary_pressure(i), liquid_saturation(i), &
                          dsat_dpres(i), dsat_dpres_numerical(i)
  enddo
  close(86)

 ! calculate capillary pressure as a function of saturation
  do i = 1, num_values
    liquid_saturation(i) = dble(i-1)*0.01d0
    if (liquid_saturation(i) < 1.d-7) then
      liquid_saturation(i) = 1.d-7
    else if (liquid_saturation(i) > (1.d0-1.d-7)) then
      liquid_saturation(i) = 1.d0-1.d-7
    endif
    call this%CapillaryPressure(liquid_saturation(i), &
                                capillary_pressure(i),dpc_dsatl(i),option)
    ! calculate numerical derivative dpc_dsatl_numerical
    pert = liquid_saturation(i) * perturbation
    if (liquid_saturation(i) > 0.5d0) then
      pert = -1.d0 * pert
    endif
    liquid_saturation_pert = liquid_saturation(i) + pert
    call this%CapillaryPressure(liquid_saturation_pert, &
                                capillary_pressure_pert,dummy_real,option)
    dpc_dsatl_numerical(i) = (capillary_pressure_pert - &
         & capillary_pressure(i))/pert
  enddo
  count = num_values

  write(string,*) cc_name
  string = trim(cc_name) // '_pc_from_sat.dat'
  open(unit=86,file=string)
  write(86,*) '"saturation", "capillary pressure", "dpc/dsat", &
              &dpc_dsat_numerical"'
  do i = 1, count
    write(86,'(4es14.6)') liquid_saturation(i), capillary_pressure(i), &
                          dpc_dsatl(i), dpc_dsatl_numerical(i)
  enddo
  close(86)

end subroutine SFBaseTest

! ************************************************************************** !
! ************************************************************************** !

subroutine RPFBaseRelPerm(this,liquid_saturation,relative_permeability, &
                            dkr_sat,option)
  use Option_module

  implicit none

  class(rel_perm_func_base_type) :: this
  PetscReal, intent(in) :: liquid_saturation
  PetscReal, intent(out) :: relative_permeability
  PetscReal, intent(out) :: dkr_sat
  type(option_type), intent(inout) :: option

  option%io_buffer = 'RPFBaseRelPerm must be extended.'
  call PrintErrMsg(option)

end subroutine RPFBaseRelPerm

! ************************************************************************** !

function RPFBaseGetResidualSaturation(this)

  implicit none

  class(rel_perm_func_base_type) :: this

  PetscReal :: RPFBaseGetResidualSaturation

  RPFBaseGetResidualSaturation = this%Sr

end function RPFBaseGetResidualSaturation

! ************************************************************************** !

function RPFBaseGetNeedsToBeExtended(this)

  implicit none

  class(rel_perm_func_base_type) :: this

  PetscReal :: RPFBaseGetNeedsToBeExtended

  RPFBaseGetNeedsToBeExtended = UNINITIALIZED_DOUBLE
  print *, 'A RPFBaseGetXXX routine needs to be extended'
  stop

end function RPFBaseGetNeedsToBeExtended

! ************************************************************************** !

subroutine RPFBaseSetResidualSaturation(this,tempreal)

  implicit none

  class(rel_perm_func_base_type) :: this
  PetscReal :: tempreal

  this%Sr = tempreal

end subroutine RPFBaseSetResidualSaturation

! ************************************************************************** !

subroutine RPFBaseSetNeedsToBeExtended(this,tempreal)

  implicit none

  class(rel_perm_func_base_type) :: this
  PetscReal :: tempreal

  print *, 'A RPFBaseSetXXX routine needs to be extended'
  stop

end subroutine RPFBaseSetNeedsToBeExtended

! ************************************************************************** !

subroutine RPFBaseLiqEffectiveSaturation(this,liquid_saturation, &
                                         effective_saturation,deffsat_dsat, &
                                         option)
  use Option_module

  implicit none

  class(rel_perm_func_base_type) :: this
  PetscReal, intent(in) :: liquid_saturation
  PetscReal, intent(out) :: effective_saturation
  PetscReal, intent(out) :: deffsat_dsat
  type(option_type), intent(inout) :: option

  deffsat_dsat = 1.d0 / (1.d0 - this%Sr)
  effective_saturation = (liquid_saturation - this%Sr) * deffsat_dsat

end subroutine RPFBaseLiqEffectiveSaturation

! ************************************************************************** !

subroutine RPFBaseGasEffectiveSaturation(this,liquid_saturation, &
                                         effective_saturation,deffsat_dsat, &
                                         option)
  use Option_module

  implicit none

  class(rel_perm_func_base_type) :: this
  PetscReal, intent(in) :: liquid_saturation
  PetscReal, intent(out) :: effective_saturation
  PetscReal, intent(out) :: deffsat_dsat
  type(option_type), intent(inout) :: option

  option%io_buffer = 'RPFBaseGasEffectiveSaturation must be extended for the &
                     &current relative permeability function.'
  call PrintErrMsg(option)

end subroutine RPFBaseGasEffectiveSaturation

! ************************************************************************** !

subroutine RPFBaseTest(this,cc_name,phase,option)

  use Option_module

  implicit none

  class(rel_perm_func_base_type) :: this
  character(len=MAXWORDLENGTH) :: cc_name
  character(len=MAXWORDLENGTH) :: phase
  type(option_type), intent(inout) :: option

  character(len=MAXSTRINGLENGTH) :: string
  PetscInt :: i
  PetscInt, parameter :: num_values = 101
  PetscReal :: perturbation
  PetscReal :: liquid_saturation(num_values)
  PetscReal :: liquid_saturation_pert(num_values)
  PetscReal :: kr(num_values)
  PetscReal :: kr_pert(num_values)
  PetscReal :: dkr_dsat(num_values)
  PetscReal :: dkr_dsat_numerical(num_values)
  PetscReal :: dummy_real(num_values)

  perturbation = 1.d-6

  do i = 1, num_values
    liquid_saturation(i) = dble(i-1)*0.01d0
    call this%RelativePermeability(liquid_saturation(i),kr(i),dkr_dsat(i), &
                                   option)
    ! calculate numerical derivative dkr_dsat_numerical
    liquid_saturation_pert(i) = liquid_saturation(i) &
                                + liquid_saturation(i)*perturbation
    call this%RelativePermeability(liquid_saturation_pert(i),kr_pert(i), &
                                   dummy_real(i),option)
    if (i > 1) then
      dkr_dsat_numerical(i) = (kr_pert(i) - kr(i))/ &
                              (liquid_saturation(i)*perturbation)
    else
! Trap case of i=0 as liquid_saturation is 0 and will otherwise divide by zero
      dkr_dsat_numerical(i) = 0.0
    endif
  enddo

  write(string,*) cc_name
  string = trim(cc_name) // '_' // trim(phase) // '_rel_perm.dat'
  open(unit=86,file=string)
  write(86,*) '"saturation", "' // trim(phase) // ' relative permeability", "' &
              // trim(phase) // ' dkr/dsat", "' // trim(phase) // &
              ' dkr/dsat_numerical"'
  do i = 1, size(liquid_saturation)
    write(86,'(4es14.6)') liquid_saturation(i), kr(i), dkr_dsat(i), &
                          dkr_dsat_numerical(i)
  enddo
  close(86)

end subroutine RPFBaseTest

! ************************************************************************** !

subroutine PolynomialDestroy(poly)
  !
  ! Destroys a polynomial smoother
  !
  ! Author: Glenn Hammond
  ! Date: 09/24/14
  !

  implicit none

  type(polynomial_type), pointer :: poly

  if (.not.associated(poly)) return

  deallocate(poly)
  nullify(poly)

end subroutine PolynomialDestroy

! ************************************************************************** !

subroutine SaturationFunctionDestroy(sf)
  !
  ! Destroys a saturuation function
  !
  ! Author: Glenn Hammond
  ! Date: 09/24/14
  !

  implicit none

  class(sat_func_base_type), pointer :: sf

  if (.not.associated(sf)) return

  call PolynomialDestroy(sf%sat_poly)
  call PolynomialDestroy(sf%sat_poly)
  deallocate(sf)
  nullify(sf)

end subroutine SaturationFunctionDestroy

! ************************************************************************** !

subroutine PermeabilityFunctionDestroy(rpf)
  !
  ! Destroys a saturuation function
  !
  ! Author: Glenn Hammond
  ! Date: 09/24/14
  !

  implicit none

  class(rel_perm_func_base_type), pointer :: rpf

  if (.not.associated(rpf)) return

  call PolynomialDestroy(rpf%poly)
  deallocate(rpf)
  nullify(rpf)

end subroutine PermeabilityFunctionDestroy

end module Characteristic_Curves_Base_module
