module Material_Aux_module

#include "petsc/finclude/petscsys.h"
  use petscsys
  use PFLOTRAN_Constants_module

  implicit none

  private


  PetscInt, parameter, public :: perm_xx_index = 1
  PetscInt, parameter, public :: perm_yy_index = 2
  PetscInt, parameter, public :: perm_zz_index = 3
  PetscInt, parameter, public :: perm_xy_index = 4
  PetscInt, parameter, public :: perm_yz_index = 5
  PetscInt, parameter, public :: perm_xz_index = 6

  ! do not use 0 as an index as there is a case statement in material.F90
  ! designed to catch erroneous values outside [1,2].
  PetscInt, parameter, public :: POROSITY_CURRENT = 1
  PetscInt, parameter, public :: POROSITY_BASE = 2
  PetscInt, parameter, public :: POROSITY_INITIAL = 3

  ! Tensor to scalar conversion models
  ! default for structured grids = TENSOR_TO_SCALAR_LINEAR
  ! default for unstructured grids = TENSOR_TO_SCALAR_POTENTIAL
  ! Both are set in discretization.F90:DiscretizationReadRequiredCards()
  ! immediately after the GRID cards is read with a call to
  ! MaterialAuxSetPermTensorModel()
  PetscInt, parameter, public :: TENSOR_TO_SCALAR_LINEAR = 1
  PetscInt, parameter, public :: TENSOR_TO_SCALAR_FLOW = 2
  PetscInt, parameter, public :: TENSOR_TO_SCALAR_POTENTIAL = 3
  PetscInt, parameter, public :: TENSOR_TO_SCALAR_FLOW_FT = 4
  PetscInt, parameter, public :: TENSOR_TO_SCALAR_POTENTIAL_FT = 5

  ! flag to determine which model to use for tensor to scalar conversion
  ! of permeability
  PetscInt :: perm_tens_to_scal_model = TENSOR_TO_SCALAR_LINEAR

!  PetscInt, public :: soil_thermal_conductivity_index
!  PetscInt, public :: soil_heat_capacity_index
  PetscInt, public :: soil_compressibility_index
  PetscInt, public :: soil_reference_pressure_index
  PetscInt, public :: max_material_index
  PetscInt, public :: epsilon_index
  PetscInt, public :: half_matrix_width_index

  type, public :: material_auxvar_type
    PetscInt :: id
    PetscReal :: volume
    PetscReal :: porosity_0 ! initial porosity as defined in input file or
                            ! initial conditon
    PetscReal :: porosity_base ! base porosity prescribed by pm outside flow
                               ! (e.g. geomechanics, mineral precip/diss)
    PetscReal :: porosity ! porosity used in calculation, which may be a
                          ! function of soil compressibity, etc.
    PetscReal :: dporosity_dp
    PetscReal :: tortuosity
    PetscReal :: soil_particle_density
    PetscReal, pointer :: permeability(:)
    PetscReal, pointer :: sat_func_prop(:)
    PetscReal, pointer :: soil_properties(:) ! den, therm. cond., heat cap., epsilon, matrix length
    PetscReal, pointer :: electrical_conductivity(:) ! Geophysics -> electrical conductivity for ERT/SIP/EM
    type(fracture_auxvar_type), pointer :: fracture
    PetscReal, pointer :: geomechanics_subsurface_prop(:)
    PetscInt :: creep_closure_id

!    procedure(SaturationFunction), nopass, pointer :: SaturationFunction
!  contains
!    procedure, public :: PermeabilityTensorToScalar
!    procedure, public :: PermeabilityTensorToScalarSafe
  end type material_auxvar_type

  type, public :: fracture_auxvar_type
    PetscBool :: fracture_is_on
    PetscReal :: initial_pressure
    PetscReal :: properties(4)
    PetscReal :: vector(3) ! < 0. 0. 0. >
  end type fracture_auxvar_type

  type, public :: material_parameter_type
    PetscReal, pointer :: soil_heat_capacity(:) ! MJ/kg rock-K
    PetscReal, pointer :: soil_thermal_conductivity(:,:) ! W/m-K
  end type material_parameter_type

  type, public :: material_type
    PetscReal :: time_t, time_tpdt
    PetscInt :: num_aux
    type(material_parameter_type), pointer :: material_parameter
    type(material_auxvar_type), pointer :: auxvars(:)
  end type material_type

  ! procedure pointer declarations
  procedure(MaterialCompressSoilDummy), pointer :: &
    MaterialCompressSoilPtr => null()

  ! interface blocks
  interface
    subroutine MaterialCompressSoilDummy(auxvar,pressure,compressed_porosity, &
                                         dcompressed_porosity_dp)
    import material_auxvar_type
    implicit none
    type(material_auxvar_type), intent(in) :: auxvar
    PetscReal, intent(in) :: pressure
    PetscReal, intent(out) :: compressed_porosity
    PetscReal, intent(out) :: dcompressed_porosity_dp
    end subroutine MaterialCompressSoilDummy
  end interface

  interface MaterialCompressSoil
    procedure MaterialCompressSoilPtr
  end interface

  public :: MaterialCompressSoilDummy, &
            MaterialCompressSoilPtr, &
            MaterialCompressSoil, &
            MaterialCompressSoilBRAGFLO, &
            MaterialCompressSoilPoroExp, &
            MaterialCompressSoilLeijnse, &
            MaterialCompressSoilLinear, &
            MaterialCompressSoilQuadratic

  public :: PermeabilityTensorToScalar

  public :: MaterialAuxCreate, &
            MaterialAuxVarInit, &
            MaterialAuxVarCopy, &
            MaterialAuxVarStrip, &
            MaterialAuxVarGetValue, &
            MaterialAuxVarSetValue, &
            MaterialAuxIndexToPropertyName, &
            MaterialAuxDestroy, &
            MaterialAuxVarFractureStrip, &
            MaterialAuxSetPermTensorModel

  public :: MaterialAuxVarCompute

contains

! ************************************************************************** !

function MaterialAuxCreate()
  !
  ! Allocate and initialize auxiliary object
  !
  ! Author: Glenn Hammond
  ! Date: 01/09/14
  !

  use Option_module

  implicit none

  type(material_type), pointer :: MaterialAuxCreate

  type(material_type), pointer :: aux

  allocate(aux)
  nullify(aux%auxvars)
  allocate(aux%material_parameter)
  nullify(aux%material_parameter%soil_heat_capacity)
  nullify(aux%material_parameter%soil_thermal_conductivity)
  aux%num_aux = 0
  aux%time_t = 0.d0
  aux%time_tpdt = 0.d0

  MaterialAuxCreate => aux

end function MaterialAuxCreate

! ************************************************************************** !

subroutine MaterialAuxVarInit(auxvar,option)
  !
  ! Initialize auxiliary object
  !
  ! Author: Glenn Hammond
  ! Date: 01/09/14
  !

  use Option_module

  implicit none

  type(material_auxvar_type) :: auxvar
  type(option_type) :: option

  auxvar%id = UNINITIALIZED_INTEGER
  auxvar%volume = UNINITIALIZED_DOUBLE
  auxvar%porosity_0 = UNINITIALIZED_DOUBLE
  auxvar%porosity_base = UNINITIALIZED_DOUBLE
  auxvar%porosity = UNINITIALIZED_DOUBLE
  auxvar%dporosity_dp = 0.d0
  auxvar%tortuosity = UNINITIALIZED_DOUBLE
  auxvar%soil_particle_density = UNINITIALIZED_DOUBLE
  if (option%iflowmode /= NULL_MODE) then
    if (option%flow%full_perm_tensor) then
      allocate(auxvar%permeability(6))
    else
      allocate(auxvar%permeability(3))
    endif
    auxvar%permeability = UNINITIALIZED_DOUBLE
  else
    nullify(auxvar%permeability)
  endif
  nullify(auxvar%sat_func_prop)
  nullify(auxvar%fracture)
  auxvar%creep_closure_id = 1

  if (max_material_index > 0) then
    allocate(auxvar%soil_properties(max_material_index))
    ! initialize these to zero for now
    auxvar%soil_properties = UNINITIALIZED_DOUBLE
  else
    nullify(auxvar%soil_properties)
  endif

  nullify(auxvar%geomechanics_subsurface_prop)

  ! PJ: for geophysics
  if (option%igeopmode /= NULL_MODE) then
    ! TODO: Tensor conductivity for anisotropy
    ! using scalar for now
    allocate(auxvar%electrical_conductivity(1))
    auxvar%electrical_conductivity = UNINITIALIZED_DOUBLE
  else
    nullify(auxvar%electrical_conductivity)
  endif

end subroutine MaterialAuxVarInit

! ************************************************************************** !

subroutine MaterialAuxVarCopy(auxvar,auxvar2,option)
  !
  ! Copies an auxiliary variable
  !
  ! Author: Glenn Hammond
  ! Date: 01/09/14
  !

  use Option_module

  implicit none

  type(material_auxvar_type) :: auxvar, auxvar2
  type(option_type) :: option

  auxvar2%volume = auxvar%volume
  auxvar2%porosity_0 = auxvar%porosity_0
  auxvar2%porosity_base = auxvar%porosity_base
  auxvar2%porosity = auxvar%porosity
  auxvar2%tortuosity = auxvar%tortuosity
  auxvar2%soil_particle_density = auxvar%soil_particle_density
  if (associated(auxvar%permeability)) then
    auxvar2%permeability = auxvar%permeability
  endif
  if (associated(auxvar%sat_func_prop)) then
    auxvar2%sat_func_prop = auxvar%sat_func_prop
  endif
  if (associated(auxvar%soil_properties)) then
    auxvar2%soil_properties = auxvar%soil_properties
  endif
  auxvar2%creep_closure_id = auxvar%creep_closure_id
  if (associated(auxvar%electrical_conductivity)) then
    auxvar2%electrical_conductivity = auxvar%electrical_conductivity
  endif

end subroutine MaterialAuxVarCopy

! ************************************************************************** !

subroutine MaterialAuxSetPermTensorModel(model,option)

  use Option_module

  implicit none

  PetscInt :: model
  type(option_type) :: option

  !! simple if longwinded little safety measure here, the calling routine
  !! should also check that model is a sane number but in principle this
  !! routine should protect itself too.
  !! Please note that if you add a new model type above then you MUST add
  !! it to this little list here too.
  if (model == TENSOR_TO_SCALAR_LINEAR .OR. &
      model == TENSOR_TO_SCALAR_FLOW .OR. &
      model == TENSOR_TO_SCALAR_POTENTIAL .OR. &
      model == TENSOR_TO_SCALAR_FLOW_FT .OR. &
      model == TENSOR_TO_SCALAR_POTENTIAL_FT) then
    perm_tens_to_scal_model = model
  else
    option%io_buffer  = 'MaterialAuxSetPermTensorModel: tensor to scalar &
                        &model type is not recognized.'
    call PrintErrMsg(option)
  endif

end subroutine MaterialAuxSetPermTensorModel

! ************************************************************************** !

subroutine PermeabilityTensorToScalar(material_auxvar,dist,scalar_permeability)
  !
  ! Transforms a diagonal permeability tensor to a scalar through a dot
  ! product.
  !
  ! Author: Glenn Hammond
  ! Date: 01/09/14
  !
  ! Modified by Moise Rousseau 09/04/19 for full tensor
  !
  use Utility_module, only : Equal

  implicit none

  type(material_auxvar_type) :: material_auxvar
  ! -1 = fraction upwind
  ! 0 = magnitude
  ! 1 = unit x-dir
  ! 2 = unit y-dir
  ! 3 = unit z-dir
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal, intent(out) :: scalar_permeability

  PetscReal :: kx, ky, kz, kxy, kxz, kyz

  kx = material_auxvar%permeability(perm_xx_index)
  ky = material_auxvar%permeability(perm_yy_index)
  kz = material_auxvar%permeability(perm_zz_index)

  select case(perm_tens_to_scal_model)
    case(TENSOR_TO_SCALAR_LINEAR)
      scalar_permeability = DiagPermTensorToScalar_Linear(kx,ky,kz,dist)
    case(TENSOR_TO_SCALAR_FLOW)
      scalar_permeability = DiagPermTensorToScalar_Flow(kx,ky,kz,dist)
    case(TENSOR_TO_SCALAR_POTENTIAL)
      scalar_permeability = DiagPermTensortoScalar_Potential(kx,ky,kz,dist)
    case(TENSOR_TO_SCALAR_FLOW_FT)
      kxy = material_auxvar%permeability(perm_xy_index)
      kxz = material_auxvar%permeability(perm_xz_index)
      kyz = material_auxvar%permeability(perm_yz_index)
      scalar_permeability = &
        FullPermTensorToScalar_Flow(kx,ky,kz,kxy,kxz,kyz,dist)
    case(TENSOR_TO_SCALAR_POTENTIAL_FT)
      kxy = material_auxvar%permeability(perm_xy_index)
      kxz = material_auxvar%permeability(perm_xz_index)
      kyz = material_auxvar%permeability(perm_yz_index)
      scalar_permeability = &
        FullPermTensorToScalar_Pot(kx,ky,kz,kxy,kxz,kyz,dist)
    case default
      ! as default, just do linear
      !scalar_permeability = DiagPermTensorToScalar_Linear(kx,ky,kz,dist)
      ! as default, do perm in direction of flow
      !scalar_permeability = DiagPermTensorToScalar_Flow(kx,ky,kz,dist)
      ! as default, do perm in direction of potential gradient
      scalar_permeability = DiagPermTensorToScalar_Potential(kx,ky,kz,dist)
  end select


end subroutine PermeabilityTensorToScalar

! ************************************************************************** !

subroutine PermeabilityTensorToScalarSafe(material_auxvar,dist, &
                                          scalar_permeability)
  !
  ! Transforms a diagonal perm. tensor to a scalar through a dot product.
  ! This version will not generate NaNs for zero permeabilities
  !
  ! Author: Dave Ponting
  ! Date: 03/19/19
  !

  implicit none

  type(material_auxvar_type) :: material_auxvar

  PetscReal, intent(in) :: dist(-1:3)
  PetscReal, intent(out) :: scalar_permeability

  PetscReal :: kx, ky, kz, kxy, kxz, kyz

  kx = material_auxvar%permeability(perm_xx_index)
  ky = material_auxvar%permeability(perm_yy_index)
  kz = material_auxvar%permeability(perm_zz_index)

  select case(perm_tens_to_scal_model)
    case(TENSOR_TO_SCALAR_LINEAR)
      scalar_permeability = DiagPermTensorToScalar_Linear(kx,ky,kz,dist)
    case(TENSOR_TO_SCALAR_FLOW)
      scalar_permeability = DiagPermTensorToScalar_Flow(kx,ky,kz,dist)
    case(TENSOR_TO_SCALAR_POTENTIAL)
      scalar_permeability = DiagPermTensorToScalarPotSafe(kx,ky,kz,dist)
    case(TENSOR_TO_SCALAR_FLOW_FT)
      kxy = material_auxvar%permeability(perm_xy_index)
      kxz = material_auxvar%permeability(perm_xz_index)
      kyz = material_auxvar%permeability(perm_yz_index)
      scalar_permeability = &
        FullPermTensorToScalar_Flow(kx,ky,kz,kxy,kxz,kyz,dist)
    case(TENSOR_TO_SCALAR_POTENTIAL_FT)
      kxy = material_auxvar%permeability(perm_xy_index)
      kxz = material_auxvar%permeability(perm_xz_index)
      kyz = material_auxvar%permeability(perm_yz_index)
      scalar_permeability = &
        FullPermTensorToScalarPotSafe(kx,ky,kz,kxy,kxz,kyz,dist)
    case default
      scalar_permeability = DiagPermTensorToScalarPotSafe(kx,ky,kz,dist)
  end select

end subroutine PermeabilityTensorToScalarSafe

! ************************************************************************** !

function DiagPermTensorToScalar_Linear(kx,ky,kz,dist)
  implicit none
  PetscReal :: DiagPermTensorToScalar_Linear
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal :: kx,ky,kz

  DiagPermTensorToScalar_Linear = kx*dabs(dist(1))+ky*dabs(dist(2))+&
                                  kz*dabs(dist(3))

end function DiagPermTensorToScalar_Linear

! ************************************************************************** !

function DiagPermTensorToScalar_Flow(kx,ky,kz,dist)

  !Permeability in the direction of flow

  implicit none
  PetscReal :: DiagPermTensorToScalar_Flow
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal :: kx,ky,kz

  DiagPermTensorToScalar_Flow = kx*dabs(dist(1))**2.0 + &
                                     ky*dabs(dist(2))**2.0 + &
                                     kz*dabs(dist(3))**2.0

end function DiagPermTensorToScalar_Flow

! ************************************************************************** !

function FullPermTensorToScalar_Flow(kx,ky,kz,kxy,kxz,kyz,dist)

  ! Permeability in the direction of flow
  ! Include non diagonal term of the full symetric permeability tensor
  !
  ! Author: Moise Rousseau
  ! Date: 08/26/19

  implicit none

  PetscReal :: FullPermTensorToScalar_Flow
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal :: kx,ky,kz,kxy,kxz,kyz

  FullPermTensorToScalar_Flow = kx*dabs(dist(1))**2.0 + &
                                ky*dabs(dist(2))**2.0 + &
                                kz*dabs(dist(3))**2.0 + &
                                2*kxy*dist(1)*dist(2) + &
                                2*kxz*dist(1)*dist(3) + &
                                2*kyz*dist(2)*dist(3)

end function FullPermTensorToScalar_Flow

! ************************************************************************** !

function DiagPermTensorToScalar_Potential(kx,ky,kz,dist)

  !Permeability in the direction of the potential gradient

  implicit none
  PetscReal :: DiagPermTensorToScalar_Potential
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal :: kx,ky,kz

  DiagPermTensorToScalar_Potential = 1.d0/(dist(1)*dist(1)/kx + &
                                         dist(2)*dist(2)/ky + &
                                         dist(3)*dist(3)/kz)

end function DiagPermTensorToScalar_Potential

! ************************************************************************** !

function FullPermTensorToScalar_Pot(kx,ky,kz,kxy,kxz,kyz,dist)

  ! Permeability in the direction of the potential gradient
  ! Include off diagonal term
  ! Not working
  !
  ! Author: Moise Rousseau
  ! Date: 08/26/19

  implicit none
  PetscReal :: FullPermTensorToScalar_Pot
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal :: kx,ky,kz,kxy,kxz,kyz

  FullPermTensorToScalar_Pot = 1.d0/(dist(1)*dist(1)/kx + &
                               dist(2)*dist(2)/ky + &
                               dist(3)*dist(3)/kz + &
                               2*dist(1)*dist(2)/kxy + &
                               2*dist(1)*dist(3)/kxz + &
                               2*dist(2)*dist(3)/kyz)

end function FullPermTensorToScalar_Pot

! ************************************************************************** !

function DiagPermTensorToScalarPotSafe(kx,ky,kz,dist)

  ! Permeability in the direction of the potential gradient
  ! This version will not generate NaNs for zero permeabilities
  !
  ! Author: Dave Ponting
  ! Date: 03/19/19
  !

  implicit none
  PetscReal :: DiagPermTensorToScalarPotSafe
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal :: kx, ky, kz, kxi, kyi, kzi, den, deni

  !  Form safe inverse permeabilities

  kxi = 0.0
  kyi = 0.0
  kzi = 0.0

  if (kx>0.0) kxi = 1.0/kx
  if (ky>0.0) kyi = 1.0/ky
  if (kz>0.0) kzi = 1.0/kz

  !  Form denominator

  den = dist(1)*dist(1)*kxi + &
        dist(2)*dist(2)*kyi + &
        dist(3)*dist(3)*kzi

  !  Form safe inverse denominator

  deni = 0.0
  if (den>0.0) deni=1.0/den

  !  Store final value

  DiagPermTensorToScalarPotSafe = deni

end function DiagPermTensorToScalarPotSafe

! ************************************************************************** !

function FullPermTensorToScalarPotSafe(kx,ky,kz,kxy,kxz,kyz,dist)

  ! Permeability in the direction of the potential gradient
  ! This version will not generate NaNs for zero permeabilities
  !
  ! Author: Dave Ponting
  ! Date: 03/19/19
  !
  ! Modify to include non diagonal term
  ! Not working for instance
  !
  ! Author: Moise Rousseau
  ! Date: 08/26/19

  implicit none

  PetscReal :: FullPermTensorToScalarPotSafe
  PetscReal, intent(in) :: dist(-1:3)
  PetscReal :: kx, ky, kz, kxi, kyi, kzi, den, deni
  PetscReal :: kxy, kxz, kyz, kxyi, kxzi, kyzi

  !  Form safe inverse permeabilities

  kxi = 0.0
  kyi = 0.0
  kzi = 0.0
  kxyi = 0.0
  kxzi = 0.0
  kyzi = 0.0

  if (kx>0.0) kxi = 1.0/kx
  if (ky>0.0) kyi = 1.0/ky
  if (kz>0.0) kzi = 1.0/kz
  if (kxy>0.0) kxyi = 1.0/kxy
  if (kxz>0.0) kxzi = 1.0/kxz
  if (kyz>0.0) kyzi = 1.0/kyz

  !  Form denominator

  den = dist(1)*dist(1)*kxi + &
        dist(2)*dist(2)*kyi + &
        dist(3)*dist(3)*kzi + &
        2*dist(1)*dist(2)*kxyi + &
        2*dist(1)*dist(3)*kxzi + &
        2*dist(2)*dist(3)*kyzi

  !  Form safe inverse denominator

  deni = 0.0
  if (den>0.0) deni=1.0/den

  !  Store final value

  FullPermTensorToScalarPotSafe = deni

end function FullPermTensorToScalarPotSafe

! ************************************************************************** !

function MaterialAuxVarGetValue(material_auxvar,ivar)
  !
  ! Returns the value of an entry in material_auxvar_type based on ivar.
  !
  ! Author: Glenn Hammond
  ! Date: 03/28/14
  !

  use Variables_module

  implicit none

  type(material_auxvar_type) :: material_auxvar
  PetscInt :: ivar

  PetscReal :: MaterialAuxVarGetValue

  MaterialAuxVarGetValue = UNINITIALIZED_DOUBLE
  select case(ivar)
    case(VOLUME)
      MaterialAuxVarGetValue = material_auxvar%volume
    case(INITIAL_POROSITY)
      MaterialAuxVarGetValue = material_auxvar%porosity_0
    case(BASE_POROSITY)
      MaterialAuxVarGetValue = material_auxvar%porosity_base
    case(POROSITY)
      MaterialAuxVarGetValue = material_auxvar%porosity
    case(TORTUOSITY)
      MaterialAuxVarGetValue = material_auxvar%tortuosity
    case(PERMEABILITY_X)
      MaterialAuxVarGetValue = material_auxvar%permeability(perm_xx_index)
    case(PERMEABILITY_Y)
      MaterialAuxVarGetValue = material_auxvar%permeability(perm_yy_index)
    case(PERMEABILITY_Z)
      MaterialAuxVarGetValue = material_auxvar%permeability(perm_zz_index)
    case(PERMEABILITY_XY,PERMEABILITY_YZ,PERMEABILITY_XZ)
      if (size(material_auxvar%permeability) > 3) then
        select case(ivar)
          case(PERMEABILITY_XY)
            MaterialAuxVarGetValue = material_auxvar%permeability(perm_xy_index)
          case(PERMEABILITY_YZ)
            MaterialAuxVarGetValue = material_auxvar%permeability(perm_yz_index)
          case(PERMEABILITY_XZ)
            MaterialAuxVarGetValue = material_auxvar%permeability(perm_xz_index)
        end select
      else
        MaterialAuxVarGetValue = 0.d0
      endif
    case(SOIL_COMPRESSIBILITY)
      MaterialAuxVarGetValue = material_auxvar% &
                                 soil_properties(soil_compressibility_index)
    case(SOIL_REFERENCE_PRESSURE)
      MaterialAuxVarGetValue = material_auxvar% &
                                 soil_properties(soil_reference_pressure_index)
    case(ELECTRICAL_CONDUCTIVITY)
      MaterialAuxVarGetValue = material_auxvar%electrical_conductivity(1)
    case default
      print *, 'Unrecognized variable in MaterialAuxVarGetValue: ', ivar
      stop
  end select

end function MaterialAuxVarGetValue

! ************************************************************************** !

subroutine MaterialAuxVarSetValue(material_auxvar,ivar,value)
  !
  ! Sets the value of an entry in material_auxvar_type based on ivar.
  !
  ! Author: Glenn Hammond
  ! Date: 03/28/14
  !

  use Variables_module

  implicit none

  type(material_auxvar_type) :: material_auxvar
  PetscInt :: ivar
  PetscReal :: value

  select case(ivar)
    case(VOLUME)
      material_auxvar%volume = value
    case(INITIAL_POROSITY)
      material_auxvar%porosity_0 = value
    case(BASE_POROSITY)
      material_auxvar%porosity_base = value
    case(POROSITY)
      material_auxvar%porosity = value
    case(TORTUOSITY)
      material_auxvar%tortuosity = value
    case(EPSILON)
      material_auxvar%soil_properties(epsilon_index) = value
    case(HALF_MATRIX_WIDTH)
      material_auxvar%soil_properties(half_matrix_width_index) = value
    case(PERMEABILITY_X)
      material_auxvar%permeability(perm_xx_index) = value
    case(PERMEABILITY_Y)
      material_auxvar%permeability(perm_yy_index) = value
    case(PERMEABILITY_Z)
      material_auxvar%permeability(perm_zz_index) = value
    case(PERMEABILITY_XY)
      material_auxvar%permeability(perm_xy_index) = value
    case(PERMEABILITY_YZ)
      material_auxvar%permeability(perm_yz_index) = value
    case(PERMEABILITY_XZ)
      material_auxvar%permeability(perm_xz_index) = value
    case(SOIL_COMPRESSIBILITY)
      material_auxvar%soil_properties(soil_compressibility_index) = value
    case(SOIL_REFERENCE_PRESSURE)
      material_auxvar%soil_properties(soil_reference_pressure_index) = value
    case(ELECTRICAL_CONDUCTIVITY)
      material_auxvar%electrical_conductivity(1) = value
    case default
      print *, 'Unrecognized variable in MaterialAuxVarSetValue: ', ivar
      stop
  end select

end subroutine MaterialAuxVarSetValue

! ************************************************************************** !

subroutine MaterialAuxVarCompute(auxvar,pressure)
  !
  ! Updates secondary material properties that are a function of state
  ! variables
  !
  ! Author: Glenn Hammond
  ! Date: 08/21/19
  !

  implicit none

  type(material_auxvar_type), intent(inout) :: auxvar
  PetscReal, intent(in) :: pressure

  auxvar%porosity = auxvar%porosity_base
  auxvar%dporosity_dp = 0.d0
  if (soil_compressibility_index > 0) then
    call MaterialCompressSoil(auxvar,pressure,auxvar%porosity, &
                              auxvar%dporosity_dp)
  endif

end subroutine MaterialAuxVarCompute

! ************************************************************************** !

subroutine MaterialCompressSoilLeijnse(auxvar,pressure, &
                                       compressed_porosity, &
                                       dcompressed_porosity_dp)
  !
  ! Calculates soil matrix compression based on Leijnse, 1992.
  !
  ! Author: Glenn Hammond
  ! Date: 01/14/14
  !

  implicit none

  type(material_auxvar_type), intent(in) :: auxvar
  PetscReal, intent(in) :: pressure
  PetscReal, intent(out) :: compressed_porosity
  PetscReal, intent(out) :: dcompressed_porosity_dp

  PetscReal :: compressibility
  PetscReal :: compression
  PetscReal :: tempreal

  compressibility = auxvar%soil_properties(soil_compressibility_index)
  compression = &
    exp(-1.d0 * compressibility * &
        (pressure - auxvar%soil_properties(soil_reference_pressure_index)))
  tempreal = (1.d0 - auxvar%porosity_base) * compression
  compressed_porosity = 1.d0 - tempreal
  dcompressed_porosity_dp = tempreal * compressibility

end subroutine MaterialCompressSoilLeijnse

! ************************************************************************** !

subroutine MaterialCompressSoilBRAGFLO(auxvar,pressure, &
                                       compressed_porosity, &
                                       dcompressed_porosity_dp)
  !
  ! Calculates soil matrix compression based on Eq. 9.6.9 of BRAGFLO
  !
  ! Author: Glenn Hammond
  ! Date: 01/14/14
  !

  implicit none

  type(material_auxvar_type), intent(in) :: auxvar
  PetscReal, intent(in) :: pressure
  PetscReal, intent(out) :: compressed_porosity
  PetscReal, intent(out) :: dcompressed_porosity_dp

  PetscReal :: compressibility


  ! convert to pore compressiblity by dividing by base porosity
  compressibility = auxvar%soil_properties(soil_compressibility_index) / &
                    auxvar%porosity_base
  compressed_porosity = auxvar%porosity_base * &
    exp(compressibility * &
        (pressure - auxvar%soil_properties(soil_reference_pressure_index)))
  dcompressed_porosity_dp = compressibility * compressed_porosity

end subroutine MaterialCompressSoilBRAGFLO

! ************************************************************************** !

subroutine MaterialCompressSoilLinear(auxvar,pressure, &
                                      compressed_porosity, &
                                      dcompressed_porosity_dp)
  !
  ! Calculates soil matrix compression for standard constant
  ! aquifer compressibility
  !
  ! variable 'alpha' is Freeze and Cherry, 1982
  !
  ! Author: Danny Birdsell and Satish Karra
  ! Date: 07/26/2016
  !

  implicit none

  type(material_auxvar_type), intent(in) :: auxvar
  PetscReal, intent(in) :: pressure
  PetscReal, intent(out) :: compressed_porosity
  PetscReal, intent(out) :: dcompressed_porosity_dp

  PetscReal :: compressibility

  compressibility = auxvar%soil_properties(soil_compressibility_index)
  compressed_porosity = auxvar%porosity_base + compressibility * &
            (pressure - auxvar%soil_properties(soil_reference_pressure_index))
  dcompressed_porosity_dp = compressibility

end subroutine MaterialCompressSoilLinear

! ************************************************************************** !

subroutine MaterialCompressSoilPoroExp(auxvar,pressure, &
                                       compressed_porosity, &
                                       dcompressed_porosity_dp)
  !
  ! Calculates soil matrix compression based on Eq. 9.6.9 of BRAGFLO
  !
  ! Author: Glenn Hammond
  ! Date: 01/14/14
  !

  implicit none

  type(material_auxvar_type), intent(in) :: auxvar
  PetscReal, intent(in) :: pressure
  PetscReal, intent(out) :: compressed_porosity
  PetscReal, intent(out) :: dcompressed_porosity_dp

  PetscReal :: compressibility

  compressibility = auxvar%soil_properties(soil_compressibility_index)
  compressed_porosity = auxvar%porosity_base * &
    exp(compressibility * &
        (pressure - auxvar%soil_properties(soil_reference_pressure_index)))
  dcompressed_porosity_dp = compressibility * compressed_porosity

end subroutine MaterialCompressSoilPoroExp

! ************************************************************************** !

subroutine MaterialCompressSoilQuadratic(auxvar,pressure, &
                                         compressed_porosity, &
                                         dcompressed_porosity_dp)
  !
  ! Calculates soil matrix compression based on a quadratic model
  ! This is thedefaul model adopted in ECLIPSE
  !
  ! Author: Paolo Orsini
  ! Date: 02/27/17
  !

  implicit none

  type(material_auxvar_type), intent(in) :: auxvar
  PetscReal, intent(in) :: pressure
  PetscReal, intent(out) :: compressed_porosity
  PetscReal, intent(out) :: dcompressed_porosity_dp

  PetscReal :: compressibility
  PetscReal :: compress_factor

  compressibility = auxvar%soil_properties(soil_compressibility_index)

  compress_factor = compressibility * &
          (pressure - auxvar%soil_properties(soil_reference_pressure_index))

  compressed_porosity = auxvar%porosity_base * &
          ( 1.0 + compress_factor + (compress_factor**2)/2.0 )

  dcompressed_porosity_dp = auxvar%porosity_base * &
          ( 1.0 + compress_factor) * compressibility

end subroutine MaterialCompressSoilQuadratic

! ************************************************************************** !

function MaterialAuxIndexToPropertyName(i)
  !
  ! Returns the name of the soil property associated with an index
  !
  ! Author: Glenn Hammond
  ! Date: 07/06/16
  !

  implicit none

  PetscInt :: i

  character(len=MAXWORDLENGTH) :: MaterialAuxIndexToPropertyName

  if (i == soil_compressibility_index) then
    MaterialAuxIndexToPropertyName = 'soil compressibility'
  else if (i == soil_reference_pressure_index) then
    MaterialAuxIndexToPropertyName = 'soil reference pressure'
  else if (i == epsilon_index) then
   MaterialAuxIndexToPropertyName = 'multicontinuum epsilon'
  else if (i == half_matrix_width_index) then
    MaterialAuxIndexToPropertyName = 'half matrix width'
!  else if (i == soil_thermal_conductivity_index) then
!    MaterialAuxIndexToPropertyName = 'soil thermal conductivity'
!  else if (i == soil_heat_capacity_index) then
!    MaterialAuxIndexToPropertyName = 'soil heat capacity'
  else
    MaterialAuxIndexToPropertyName = 'unknown property'
  end if

end function MaterialAuxIndexToPropertyName

! ************************************************************************** !

subroutine MaterialAuxVarFractureStrip(fracture)
  !
  ! Deallocates a fracture auxiliary object
  !
  ! Author: Glenn Hammond
  ! Date: 06/14/17
  !
  use Utility_module, only : DeallocateArray

  implicit none

  type(fracture_auxvar_type), pointer :: fracture

  if (.not.associated(fracture)) return

  ! properties and vector are now static arrays.
  deallocate(fracture)
  nullify(fracture)

end subroutine MaterialAuxVarFractureStrip

! ************************************************************************** !

subroutine MaterialAuxVarStrip(auxvar)
  !
  ! Deallocates a material auxiliary object
  !
  ! Author: Glenn Hammond
  ! Date: 01/09/14
  !
  use Utility_module, only : DeallocateArray

  implicit none

  type(material_auxvar_type) :: auxvar

  call DeallocateArray(auxvar%permeability)
  call DeallocateArray(auxvar%sat_func_prop)
  call DeallocateArray(auxvar%soil_properties)
  call MaterialAuxVarFractureStrip(auxvar%fracture)
  if (associated(auxvar%geomechanics_subsurface_prop)) then
    call DeallocateArray(auxvar%geomechanics_subsurface_prop)
  endif
  call DeallocateArray(auxvar%electrical_conductivity)

end subroutine MaterialAuxVarStrip

! ************************************************************************** !

subroutine MaterialAuxDestroy(aux)
  !
  ! Deallocates a material auxiliary object
  !
  ! Author: Glenn Hammond
  ! Date: 03/02/11
  !
  use Utility_module, only : DeallocateArray

  implicit none

  type(material_type), pointer :: aux

  PetscInt :: iaux

  if (.not.associated(aux)) return

  if (associated(aux%auxvars)) then
    do iaux = 1, aux%num_aux
      call MaterialAuxVarStrip(aux%auxvars(iaux))
    enddo
    deallocate(aux%auxvars)
  endif
  nullify(aux%auxvars)

  if (associated(aux%material_parameter)) then
    call DeallocateArray(aux%material_parameter%soil_heat_capacity)
    call DeallocateArray(aux%material_parameter%soil_thermal_conductivity)
  endif
  deallocate(aux%material_parameter)
  nullify(aux%material_parameter)

  deallocate(aux)
  nullify(aux)

end subroutine MaterialAuxDestroy

end module Material_Aux_module
