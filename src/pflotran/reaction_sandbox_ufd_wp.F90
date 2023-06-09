module Reaction_Sandbox_UFD_WP_class

#include "petsc/finclude/petscsys.h"
  use petscsys

! Sandbox reaction for waste packages in the DOE-NE UFD

! 1. Change all references to "WastePackage" as desired to rename the module and
!    and subroutines within the module.

  use Reaction_Sandbox_Base_class

  use Global_Aux_module
  use Reactive_Transport_Aux_module

  use PFLOTRAN_Constants_module

  implicit none

  private

  type, public, &
    extends(reaction_sandbox_base_type) :: reaction_sandbox_ufd_wp_type
    character(len=MAXWORDLENGTH) :: aqueous_species_name
    character(len=MAXWORDLENGTH) :: immobile_species_name
    PetscInt :: aqueous_species_id
    PetscInt :: immobile_species_id
    PetscReal :: rate_constant
  contains
    procedure, public :: ReadInput => WastePackageRead
    procedure, public :: Setup => WastePackageSetup
    procedure, public :: Evaluate => WastePackageReact
    procedure, public :: Destroy => WastePackageDestroy
  end type reaction_sandbox_ufd_wp_type

  public :: WastePackageCreate

contains

! ************************************************************************** !

function WastePackageCreate()
  !
  ! Allocates UFD waste package reaction object.
  !
  ! Author: Glenn Hammond
  ! Date: 02/27/14
  !

  implicit none

  class(reaction_sandbox_ufd_wp_type), pointer :: WastePackageCreate

  allocate(WastePackageCreate)
  WastePackageCreate%aqueous_species_name = ''
  WastePackageCreate%immobile_species_name = ''
  WastePackageCreate%aqueous_species_id = 0
  WastePackageCreate%immobile_species_id = 0
  WastePackageCreate%rate_constant = 0.d0
  nullify(WastePackageCreate%next)

end function WastePackageCreate

! ************************************************************************** !

subroutine WastePackageRead(this,input,option)
  !
  ! Reads input deck for UFD waste package reaction parameters
  !
  ! Author: Glenn Hammond
  ! Date: 02/27/14
  !
  use Option_module
  use String_module
  use Input_Aux_module
  use Units_module, only : UnitsConvertToInternal

  implicit none

  class(reaction_sandbox_ufd_wp_type) :: this
  type(input_type), pointer :: input
  type(option_type) :: option

  character(len=MAXWORDLENGTH) :: word, internal_units

  call InputPushBlock(input,option)
  do
    call InputReadPflotranString(input,option)
    if (InputError(input)) exit
    if (InputCheckExit(input,option)) exit

    call InputReadCard(input,option,word)
    call InputErrorMsg(input,option,'keyword', &
                       'CHEMISTRY,REACTION_SANDBOX,UFD-WP')
    call StringToUpper(word)

    select case(trim(word))

      ! WastePackage Input:

      ! CHEMISTRY
      !   ...
      !   REACTION_SANDBOX
      !   : begin user-defined input
      !     UFD_PW
      !       RATE_CONSTANT X.dX
      !       AQUEOUS_SPECIES_NAME <string>
      !       IMMOBILE_SPECIES_NAME <string)
      !     END
      !   : end user defined input
      !   END
      !   ...
      ! END

      case('AQUEOUS_SPECIES_NAME')
        call InputReadWord(input,option,this%aqueous_species_name,PETSC_TRUE)
        call InputErrorMsg(input,option,'aqueous species_name', &
                           'CHEMISTRY,REACTION_SANDBOX,UFD_WP')
      case('IMMOBILE_SPECIES_NAME')
        call InputReadWord(input,option,this%immobile_species_name,PETSC_TRUE)
        call InputErrorMsg(input,option,'immobile species_name', &
                           'CHEMISTRY,REACTION_SANDBOX,UFD-WP')
      case('RATE_CONSTANT')
        call InputReadDouble(input,option,this%rate_constant)
        call InputErrorMsg(input,option,'rate_constant', &
                           'CHEMISTRY,REACTION_SANDBOX,UFD-WP')
        internal_units = 'unitless/sec'
        call InputReadAndConvertUnits(input,this%rate_constant, &
                                internal_units,'CHEMISTRY,REACTION_SANDBOX,&
                                &UFD-WP,RATE_CONSTANT',option)
      case default
        call InputKeywordUnrecognized(input,word, &
                     'CHEMISTRY,REACTION_SANDBOX,UFD-WP',option)
    end select
  enddo
  call InputPopBlock(input,option)

end subroutine WastePackageRead

! ************************************************************************** !

subroutine WastePackageSetup(this,reaction,option)
  !
  ! Sets up the UFD waste package reaction
  !
  ! Author: Glenn Hammond
  ! Date: 02/27/14
  !

  use Reaction_Aux_module, only : reaction_rt_type, GetPrimarySpeciesIDFromName
  use Reaction_Immobile_Aux_module, only : GetImmobileSpeciesIDFromName
  use Option_module

  implicit none

  class(reaction_sandbox_ufd_wp_type) :: this
  class(reaction_rt_type) :: reaction
  type(option_type) :: option

  this%aqueous_species_id = &
    GetPrimarySpeciesIDFromName(this%aqueous_species_name, &
                                reaction,option)
  this%immobile_species_id = &
    GetImmobileSpeciesIDFromName(this%immobile_species_name, &
                                 reaction%immobile,option)

end subroutine WastePackageSetup

! ************************************************************************** !

subroutine WastePackageReact(this,Residual,Jacobian,compute_derivative, &
                             rt_auxvar,global_auxvar,material_auxvar, &
                             reaction,option)
  !
  ! Evaluates reaction storing residual and/or Jacobian
  !
  ! Author: Glenn Hammond
  ! Date: 02/27/14
  !

  use Option_module
  use Reaction_Aux_module
  use Material_Aux_module

  implicit none

  class(reaction_sandbox_ufd_wp_type) :: this
  type(option_type) :: option
  class(reaction_rt_type) :: reaction
  PetscBool :: compute_derivative
  ! the following arrays must be declared after reaction
  PetscReal :: Residual(reaction%ncomp)
  PetscReal :: Jacobian(reaction%ncomp,reaction%ncomp)
  type(reactive_transport_auxvar_type) :: rt_auxvar
  type(global_auxvar_type) :: global_auxvar
  type(material_auxvar_type) :: material_auxvar

  PetscReal :: rate
  PetscReal :: drate
  PetscInt :: idof_aqueous
  PetscInt :: idof_immobile

  ! mol/sec
  rate = this%rate_constant * &  ! 1/sec
         material_auxvar%volume * & ! m^3 bulk
         rt_auxvar%immobile(this%immobile_species_id) ! mol/m^3 bulk

  ! alway subtract contribution from residual
  idof_aqueous = this%aqueous_species_id
  idof_immobile = reaction%offset_immobile + this%immobile_species_id

  Residual(idof_aqueous) = Residual(idof_aqueous) - rate
  Residual(idof_immobile) = Residual(idof_immobile) + rate

  if (compute_derivative) then

    ! m^3 bulk/sec
    drate = this%rate_constant * &  ! 1/sec
            material_auxvar%volume ! m^3 bulk

    ! always add contribution to Jacobian
    ! units = (mol/sec)*(m^3 bulk/mol) = m^3 bulk/sec
    Jacobian(idof_aqueous,idof_immobile) = &
      Jacobian(idof_aqueous,idof_immobile) + drate

    ! units = (mol/sec)*(m^3 bulk/mol) = m^3 bulk/sec
    Jacobian(idof_immobile,idof_immobile) = &
      Jacobian(idof_immobile,idof_immobile) - drate

  endif

end subroutine WastePackageReact

! ************************************************************************** !

subroutine WastePackageDestroy(this)
  !
  ! Destroys allocatable or pointer objects created in this
  ! module
  !
  ! Author: Glenn Hammond
  ! Date: 02/27/14
  !

  implicit none

  class(reaction_sandbox_ufd_wp_type) :: this

end subroutine WastePackageDestroy

end module Reaction_Sandbox_UFD_WP_class
