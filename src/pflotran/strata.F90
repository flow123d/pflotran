module Strata_module

#include "petsc/finclude/petscsys.h"
  use petscsys

  use Region_module
  use Material_module

  use PFLOTRAN_Constants_module

  implicit none

  private

  PetscInt, parameter, public :: SET_MATERIAL_IDS_BELOW_SURFACE = 1
  PetscInt, parameter, public :: SET_MATERIAL_IDS_ABOVE_SURFACE = 2

  type, public :: strata_type
    PetscInt :: id                                       ! id of strata
    PetscBool :: active
    character(len=MAXWORDLENGTH) :: material_property_name  ! character string defining name of material to be applied
    character(len=MAXSTRINGLENGTH) :: material_property_filename  ! character string defining name of file containing materia ids
    PetscBool :: realization_dependent
    character(len=MAXWORDLENGTH) :: region_name         ! character string defining name of region to be applied
    character(len=MAXWORDLENGTH) :: dataset_name
    PetscInt :: imaterial_property                       ! id of material in material array/list
    PetscInt :: iregion                                  ! id of region in region array/list
    type(material_property_type), pointer :: material_property ! pointer to material in material array/list
    type(region_type), pointer :: region                ! pointer to region in region array/list
    PetscReal :: start_time
    PetscReal :: final_time
    PetscBool :: well
    PetscInt :: dataset_mat_id_direction
    type(strata_type), pointer :: next            ! pointer to next strata
  end type strata_type

  type, public :: strata_ptr_type
    type(strata_type), pointer :: ptr
  end type strata_ptr_type

  type, public :: strata_list_type
    PetscInt :: num_strata
    type(strata_type), pointer :: first
    type(strata_type), pointer :: last
    type(strata_ptr_type), pointer :: array(:)
  end type strata_list_type

  interface StrataCreate
    module procedure StrataCreate1
    module procedure StrataCreateFromStrata
  end interface

  public :: StrataCreate, &
            StrataCreateFromStrata, &
            StrataDestroy, &
            StrataInitList, &
            StrataAddToList, &
            StrataRead, &
            StrataWithinTimePeriod, &
            StrataEvolves, &
            StrataInputRecord, &
            StrataDestroyList

contains

! ************************************************************************** !

function StrataCreate1()
  !
  ! Creates a strata
  !
  ! Author: Glenn Hammond
  ! Date: 10/23/07
  !
  implicit none

  type(strata_type), pointer :: StrataCreate1

  type(strata_type), pointer :: strata

  allocate(strata)
  strata%id = 0
  strata%active = PETSC_TRUE
  strata%material_property_name = ""
  strata%material_property_filename = ""
  strata%dataset_name = ""
  strata%realization_dependent = PETSC_FALSE
  strata%region_name = ""
  strata%iregion = 0
  strata%imaterial_property = 0
  strata%start_time = UNINITIALIZED_DOUBLE
  strata%final_time = UNINITIALIZED_DOUBLE
  strata%well = PETSC_FALSE
  strata%dataset_mat_id_direction = SET_MATERIAL_IDS_BELOW_SURFACE
  nullify(strata%region)
  nullify(strata%material_property)
  nullify(strata%next)

  StrataCreate1 => strata

end function StrataCreate1

! ************************************************************************** !

function StrataCreateFromStrata(strata)
  !
  ! Creates a strata
  !
  ! Author: Glenn Hammond
  ! Date: 10/23/07
  !

  implicit none

  type(strata_type), pointer :: StrataCreateFromStrata
  type(strata_type), pointer :: strata

  type(strata_type), pointer :: new_strata

  new_strata => StrataCreate1()

  new_strata%id = strata%id
  new_strata%active = strata%active
  new_strata%material_property_name = strata%material_property_name
  new_strata%material_property_filename = strata%material_property_filename
  new_strata%realization_dependent = strata%realization_dependent
  new_strata%region_name = strata%region_name
  new_strata%iregion = strata%iregion
  new_strata%start_time = strata%start_time
  new_strata%final_time = strata%final_time
  new_strata%well = strata%well
  new_strata%dataset_name = strata%dataset_name
  new_strata%dataset_mat_id_direction = strata%dataset_mat_id_direction
  ! keep these null
  nullify(new_strata%region)
  nullify(new_strata%material_property)
  nullify(new_strata%next)

  StrataCreateFromStrata => new_strata

end function StrataCreateFromStrata

! ************************************************************************** !

subroutine StrataInitList(list)
  !
  ! Initializes a strata list
  !
  ! Author: Glenn Hammond
  ! Date: 11/01/07
  !

  implicit none

  type(strata_list_type) :: list

  nullify(list%first)
  nullify(list%last)
  nullify(list%array)
  list%num_strata = 0

end subroutine StrataInitList

! ************************************************************************** !

subroutine StrataRead(strata,input,option)
  !
  ! Reads a strata from the input file
  !
  ! Author: Glenn Hammond
  ! Date: 11/01/07
  !
  use Input_Aux_module
  use Option_module
  use String_module
  use Units_module

  implicit none

  type(strata_type) :: strata
  type(input_type), pointer :: input
  type(option_type) :: option

  character(len=MAXWORDLENGTH) :: keyword
  character(len=MAXWORDLENGTH) :: internal_units

  input%ierr = 0
  call InputPushBlock(input,option)
  do

    call InputReadPflotranString(input,option)

    if (InputCheckExit(input,option)) exit

    call InputReadCard(input,option,keyword)
    call InputErrorMsg(input,option,'keyword','STRATA')

    select case(trim(keyword))

      case('FILE')
        call InputReadFilename(input,option,strata%material_property_filename)
        call InputErrorMsg(input,option,'material property filename','STRATA')
      case('REGION')
        call InputReadWord(input,option,strata%region_name,PETSC_TRUE)
        call InputErrorMsg(input,option,'region name','STRATA')
      case('MATERIAL')
        call InputReadWord(input,option,strata%material_property_name, &
                           PETSC_TRUE)
        call InputErrorMsg(input,option,'material property name','STRATA')
      case('SURFACE_DATASET')
        call InputReadWord(input,option,strata%dataset_name,PETSC_TRUE)
        call InputErrorMsg(input,option,'dataset name','STRATA')
      case('SET_MATERIAL_IDS_BELOW_SURFACE')
        strata%dataset_mat_id_direction = SET_MATERIAL_IDS_BELOW_SURFACE
      case('SET_MATERIAL_IDS_ABOVE_SURFACE')
        strata%dataset_mat_id_direction = SET_MATERIAL_IDS_ABOVE_SURFACE
      case('REALIZATION_DEPENDENT')
        strata%realization_dependent = PETSC_TRUE
      case('START_TIME')
        call InputReadDouble(input,option,strata%start_time)
        call InputErrorMsg(input,option,keyword,'STRATA')
        internal_units = 'sec'
        call InputReadAndConvertUnits(input,strata%start_time, &
                                      internal_units,'STRATA,START_TIME', &
                                      option)
      case('FINAL_TIME')
        call InputReadDouble(input,option,strata%final_time)
        call InputErrorMsg(input,option,keyword,'STRATA')
        internal_units = 'sec'
        call InputReadAndConvertUnits(input,strata%final_time, &
                                      internal_units,'STRATA,FINAL_TIME', &
                                      option)
      case('WELL')
        strata%well = PETSC_TRUE
      case('INACTIVE')
        strata%active = PETSC_FALSE
      case default
        call InputKeywordUnrecognized(input,keyword,'STRATA',option)
    end select

  enddo
  call InputPopBlock(input,option)

  if (len_trim(strata%region_name) == 0 .and. &
      len_trim(strata%dataset_name) == 0 .and. &
      len_trim(strata%material_property_name) > 0) then
    option%io_buffer = 'The MATERIAL property "' // &
      trim(strata%material_property_name) // '" must have an associated &
      &REGION or SURFACE_DATASET in the STRATA block.  Otherwise, please &
      &use "FILE <filename>" to read material IDs from a file.'
    call PrintErrMsg(option)
  endif

  if ((Initialized(strata%start_time) .and. &
       Uninitialized(strata%final_time)) .or. &
      (Uninitialized(strata%start_time) .and. &
       Initialized(strata%final_time))) then
    option%io_buffer = &
      'Both START_TIME and FINAL_TIME must be set for STRATA with region "' // &
      trim(strata%region_name) // '".'
    call PrintErrMsg(option)
  endif
  if (Initialized(strata%start_time)) then
    option%flow%transient_porosity = PETSC_TRUE
  endif

end subroutine StrataRead

! ************************************************************************** !

subroutine StrataAddToList(new_strata,list)
  !
  ! Adds a new strata to a strata list
  !
  ! Author: Glenn Hammond
  ! Date: 11/01/07
  !

  implicit none

  type(strata_type), pointer :: new_strata
  type(strata_list_type) :: list

  list%num_strata = list%num_strata + 1
  new_strata%id = list%num_strata
  if (.not.associated(list%first)) list%first => new_strata
  if (associated(list%last)) list%last%next => new_strata
  list%last => new_strata

end subroutine StrataAddToList

! ************************************************************************** !

function StrataWithinTimePeriod(strata,time)
  !
  ! Determines whether the strata is defined for the time specified.
  !
  ! Author: Glenn Hammond
  ! Date: 10/07/14
  !
  implicit none

  type(strata_type) :: strata
  PetscReal :: time

  PetscBool :: StrataWithinTimePeriod

  StrataWithinTimePeriod = PETSC_TRUE
  if (Initialized(strata%start_time)) then
    StrataWithinTimePeriod = (time >= strata%start_time - 1.d0 .and. &
                              time < strata%final_time - 1.d0)
  endif

end function StrataWithinTimePeriod

! ************************************************************************** !

function StrataEvolves(strata_list)
  !
  ! Determines whether the strata is defined for the time specified.
  !
  ! Author: Glenn Hammond
  ! Date: 10/07/14
  !
  implicit none

  type(strata_list_type) :: strata_list

  type(strata_type), pointer :: strata

  PetscBool :: StrataEvolves

  StrataEvolves = PETSC_FALSE
  strata => strata_list%first
  do
    if (.not.associated(strata)) exit
    if (Initialized(strata%start_time) .or. Initialized(strata%final_time)) then
      StrataEvolves = PETSC_TRUE
      exit
    endif
    strata => strata%next
  enddo

end function StrataEvolves

! **************************************************************************** !

subroutine StrataInputRecord(strata_list)
  !
  ! Prints ingested strata information to the input record file
  !
  ! Author: Jenn Frederick
  ! Date: 04/07/2016
  !

  implicit none

  type(strata_list_type), pointer :: strata_list

  type(strata_type), pointer :: cur_strata
  character(len=MAXWORDLENGTH) :: word1
  PetscInt :: id = INPUT_RECORD_UNIT

  write(id,'(a)') ' '
  write(id,'(a)') '---------------------------------------------------------&
                  &-----------------------'
  write(id,'(a29)',advance='no') '---------------------------: '
  write(id,'(a)') 'STRATA'

  cur_strata => strata_list%first
  do
    if (.not.associated(cur_strata)) exit

    write(id,'(a29)',advance='no') 'strata material name: '
    write(id,'(a)') adjustl(trim(cur_strata%material_property_name))

    if (len_trim(cur_strata%material_property_filename) > 0) then
      write(id,'(a29)',advance='no') 'from file: '
      write(id,'(a)') adjustl(trim(cur_strata%material_property_filename))
    endif

    if (len_trim(cur_strata%dataset_name) > 0) then
      write(id,'(a29)',advance='no') 'from dataset: '
      write(id,'(a)') adjustl(trim(cur_strata%dataset_name))
    endif

    write(id,'(a29)',advance='no') 'associated region name: '
    write(id,'(a)') adjustl(trim(cur_strata%region_name))

    write(id,'(a29)',advance='no') 'strata is: '
    if (cur_strata%active) then
      write(id,'(a)') 'active'
    else
      write(id,'(a)') 'inactive'
    endif

    write(id,'(a29)',advance='no') 'realization-dependent: '
    if (cur_strata%realization_dependent) then
      write(id,'(a)') 'TRUE'
    else
      write(id,'(a)') 'FALSE'
    endif

    if (initialized(cur_strata%start_time)) then
      write(id,'(a29)',advance='no') 'start time: '
      write(word1,*) cur_strata%start_time
      write(id,'(a)') adjustl(trim(word1)) // ' sec'
      write(id,'(a29)',advance='no') 'final time: '
      write(word1,*) cur_strata%final_time
      write(id,'(a)') adjustl(trim(word1)) // ' sec'
    endif

    write(id,'(a29)') '---------------------------: '
    cur_strata => cur_strata%next
  enddo

end subroutine StrataInputRecord

! ************************************************************************** !

subroutine StrataDestroyList(strata_list)
  !
  ! Deallocates a list of stratas
  !
  ! Author: Glenn Hammond
  ! Date: 11/01/07
  !

  implicit none

  type(strata_list_type), pointer :: strata_list

  type(strata_type), pointer :: strata, prev_strata


  strata => strata_list%first
  do
    if (.not.associated(strata)) exit
    prev_strata => strata
    strata => strata%next
    call StrataDestroy(prev_strata)
  enddo

  strata_list%num_strata = 0
  nullify(strata_list%first)
  nullify(strata_list%last)
  if (associated(strata_list%array)) deallocate(strata_list%array)
  nullify(strata_list%array)

  deallocate(strata_list)
  nullify(strata_list)

end subroutine StrataDestroyList

! ************************************************************************** !

subroutine StrataDestroy(strata)
  !
  ! Destroys a strata
  !
  ! Author: Glenn Hammond
  ! Date: 10/23/07
  !

  implicit none

  type(strata_type), pointer :: strata

  if (.not.associated(strata)) return

  ! since strata%region is a pointer to a region in a list, nullify instead
  ! of destroying since the list will be destroyed separately
  nullify(strata%region)

  deallocate(strata)
  nullify(strata)

end subroutine StrataDestroy

end module Strata_module
