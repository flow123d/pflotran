module Output_VTK_module

#include "petsc/finclude/petscvec.h"
  use petscvec
  use Logging_module
  use Output_Aux_module
  use Output_Common_module

  use PFLOTRAN_Constants_module

  implicit none

  private

  PetscInt, parameter :: VTK_INTEGER = 0
  PetscInt, parameter :: VTK_REAL = 1

  public :: OutputVTK

contains

! ************************************************************************** !

subroutine OutputVTK(realization_base)

  use Realization_Base_class, only : realization_base_type
  use Discretization_module
  use Grid_module
  use Grid_Structured_module
  use Option_module
  use Field_module
  use Patch_module
  use String_module

  use Reaction_Aux_module
  use Variables_module

  implicit none

  class(realization_base_type) :: realization_base

  character(len=MAXSTRINGLENGTH) :: filename
  character(len=MAXWORDLENGTH) :: word
  type(grid_type), pointer :: grid
  type(option_type), pointer :: option
  type(discretization_type), pointer :: discretization
  type(field_type), pointer :: field
  type(patch_type), pointer :: patch
  class(reaction_rt_type), pointer :: reaction
  type(output_option_type), pointer :: output_option
  type(output_variable_type), pointer :: cur_variable
  Vec :: global_vec
  Vec :: natural_vec
  PetscErrorCode :: ierr

  discretization => realization_base%discretization
  patch => realization_base%patch
  grid => patch%grid
  option => realization_base%option
  field => realization_base%field
  reaction => ReactionCast(realization_base%reaction_base)
  output_option => realization_base%output_option

  ! open file
  filename = OutputFilename(output_option,option,'vtk','')

  if (OptionIsIORank(option)) then
    option%io_buffer = ' --> write vtk output file: ' // trim(filename)
    call PrintMsg(option)
    open(unit=OUTPUT_UNIT,file=filename,action="write")

    ! write header
    write(OUTPUT_UNIT,'(''# vtk DataFile Version 2.0'')')
    ! write title
    write(OUTPUT_UNIT,'(''PFLOTRAN output'')')
    write(OUTPUT_UNIT,'(''ASCII'')')
    write(OUTPUT_UNIT,'(''DATASET UNSTRUCTURED_GRID'')')
  endif

  call DiscretizationCreateVector(discretization,ONEDOF,global_vec,GLOBAL, &
                                  option)
  call DiscretizationCreateVector(discretization,ONEDOF,natural_vec,NATURAL, &
                                  option)

  ! write out coordinates
  call WriteVTKGrid(OUTPUT_UNIT,realization_base)

  if (OptionIsIORank(option)) then
    write(OUTPUT_UNIT,'(''CELL_DATA '',i8)') grid%nmax
  endif

  cur_variable => output_option%output_snap_variable_list%first
  do
    if (.not.associated(cur_variable)) exit
    call OutputGetVariableArray(realization_base,global_vec,cur_variable)
    call DiscretizationGlobalToNatural(discretization,global_vec, &
                                        natural_vec,ONEDOF)
    word=trim(cur_variable%name)
    call StringSwapChar(word," ","_")
    if (cur_variable%iformat == 0) then
      call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base, &
        word,natural_vec,VTK_REAL)
    else
      call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base, &
        word,natural_vec,VTK_INTEGER)
    endif
    cur_variable => cur_variable%next
  enddo

  call VecDestroy(natural_vec,ierr);CHKERRQ(ierr)
  call VecDestroy(global_vec,ierr);CHKERRQ(ierr)

  if (OptionIsIORank(option)) close(OUTPUT_UNIT)

#if 1
  if (output_option%print_vtk_vel_cent) then
    call OutputVelocitiesVTK(realization_base)
  endif
#endif

#if 0
  if (output_option%print_vtk_vel_cent) then
    if (grid%structured_grid%nx > 1) then
      call OutputFluxVelocitiesVTK(realization_base,LIQUID_PHASE, &
                                          X_DIRECTION)
      select case(option%iflowmode)
        case(MPH_MODE,G_MODE,H_MODE,WF_MODE)
          call OutputFluxVelocitiesVTK(realization_base,GAS_PHASE, &
                                              X_DIRECTION)
      end select
    endif
    if (grid%structured_grid%ny > 1) then
      call OutputFluxVelocitiesVTK(realization_base,LIQUID_PHASE, &
                                          Y_DIRECTION)
      select case(option%iflowmode)
        case(MPH_MODE,G_MODE,H_MODE,WF_MODE)
          call OutputFluxVelocitiesVTK(realization_base,GAS_PHASE, &
                                              Y_DIRECTION)
      end select
    endif
    if (grid%structured_grid%nz > 1) then
      call OutputFluxVelocitiesVTK(realization_base,LIQUID_PHASE, &
                                          Z_DIRECTION)
      select case(option%iflowmode)
        case(MPH_MODE,G_MODE,H_MODE,WF_MODE)
          call OutputFluxVelocitiesVTK(realization_base,GAS_PHASE, &
                                              Z_DIRECTION)
      end select
    endif
  endif
#endif

end subroutine OutputVTK

#if 1

! ************************************************************************** !

subroutine OutputVelocitiesVTK(realization_base)
  !
  ! Print velocities to Tecplot file in BLOCK format
  !
  use Realization_Base_class, only : realization_base_type, &
                                     RealizationGetVariable
  use Discretization_module
  use Grid_module
  use Option_module
  use Field_module
  use Patch_module
  use Variables_module

  implicit none

  class(realization_base_type) :: realization_base

  type(grid_type), pointer :: grid
  type(option_type), pointer :: option
  type(field_type), pointer :: field
  type(discretization_type), pointer :: discretization
  type(patch_type), pointer :: patch
  type(output_option_type), pointer :: output_option
  character(len=MAXSTRINGLENGTH) :: filename
  character(len=MAXWORDLENGTH) :: word
  Vec :: global_vec
  Vec :: natural_vec
  Vec :: global_vec_vx,global_vec_vy,global_vec_vz
  PetscErrorCode :: ierr

  patch => realization_base%patch
  grid => patch%grid
  field => realization_base%field
  option => realization_base%option
  output_option => realization_base%output_option
  discretization => realization_base%discretization

  ! open file
  filename = OutputFilename(output_option,option,'vtk','vel')

  if (OptionIsIORank(option)) then
   option%io_buffer = ' --> write vtk velocity output file: ' // &
                      trim(filename)
    call PrintMsg(option)
    open(unit=OUTPUT_UNIT,file=filename,action="write")

    ! write header
    write(OUTPUT_UNIT,'(''# vtk DataFile Version 2.0'')')
    ! write title
    write(OUTPUT_UNIT,'(''PFLOTRAN output'')')
    write(OUTPUT_UNIT,'(''ASCII'')')
    write(OUTPUT_UNIT,'(''DATASET UNSTRUCTURED_GRID'')')

  endif

  ! write blocks
  ! write out data sets
  call DiscretizationCreateVector(discretization,ONEDOF,global_vec,GLOBAL, &
                                  option)
  call DiscretizationCreateVector(discretization,ONEDOF,natural_vec,NATURAL, &
                                  option)
  call DiscretizationDuplicateVector(discretization,global_vec,global_vec_vx)
  call DiscretizationDuplicateVector(discretization,global_vec,global_vec_vy)
  call DiscretizationDuplicateVector(discretization,global_vec,global_vec_vz)

  ! write out coordinates
  call WriteVTKGrid(OUTPUT_UNIT,realization_base)

  if (OptionIsIORank(option)) then
    write(OUTPUT_UNIT,'(''CELL_DATA '',i8)') grid%nmax
  endif

  word = 'Vlx'
  call OutputGetCellCenteredVelocities(realization_base,global_vec_vx, &
                                       global_vec_vy,global_vec_vz,LIQUID_PHASE)
  call DiscretizationGlobalToNatural(discretization,global_vec_vx, &
                                     natural_vec,ONEDOF)
  call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base,word, &
                              natural_vec,VTK_REAL)
  word = 'Vly'
  call DiscretizationGlobalToNatural(discretization,global_vec_vy, &
                                     natural_vec,ONEDOF)
  call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base,word, &
                              natural_vec,VTK_REAL)
  word = 'Vlz'
  call DiscretizationGlobalToNatural(discretization,global_vec_vz, &
                                     natural_vec,ONEDOF)
  call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base,word, &
                              natural_vec,VTK_REAL)

  if (option%nphase > 1 .or. option%transport%nphase > 1) then
    word = 'Vgx'
    call OutputGetCellCenteredVelocities(realization_base,global_vec_vx, &
                                         global_vec_vy,global_vec_vz,GAS_PHASE)
    call DiscretizationGlobalToNatural(discretization,global_vec_vx, &
                                       natural_vec,ONEDOF)
    call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base,word, &
                                natural_vec,VTK_REAL)
    word = 'Vgy'
    call DiscretizationGlobalToNatural(discretization,global_vec_vy, &
                                       natural_vec,ONEDOF)
    call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base,word, &
                                natural_vec,VTK_REAL)
    word = 'Vgz'
    call DiscretizationGlobalToNatural(discretization,global_vec_vz, &
                                       natural_vec,ONEDOF)
    call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base,word, &
                                natural_vec,VTK_REAL)
  endif

  ! material id
  word = 'Material_ID'
  call RealizationGetVariable(realization_base,global_vec, &
                              MATERIAL_ID,ZERO_INTEGER)
  call DiscretizationGlobalToNatural(discretization,global_vec, &
                                     natural_vec,ONEDOF)
  call WriteVTKDataSetFromVec(OUTPUT_UNIT,realization_base,word, &
                              natural_vec,VTK_INTEGER)

  call VecDestroy(natural_vec,ierr);CHKERRQ(ierr)
  call VecDestroy(global_vec,ierr);CHKERRQ(ierr)
  call VecDestroy(global_vec_vx,ierr);CHKERRQ(ierr)
  call VecDestroy(global_vec_vy,ierr);CHKERRQ(ierr)
  call VecDestroy(global_vec_vz,ierr);CHKERRQ(ierr)

  if (OptionIsIORank(option)) close(OUTPUT_UNIT)

end subroutine OutputVelocitiesVTK
#endif

! ************************************************************************** !

subroutine WriteVTKGrid(fid,realization_base)
  !
  ! Writes a grid in VTK format
  !

  use Realization_Base_class, only : realization_base_type
  use Discretization_module
  use Grid_module
  use Option_module
  use Patch_module

  implicit none

  PetscInt :: fid
  class(realization_base_type) :: realization_base

  type(discretization_type), pointer :: discretization
  type(grid_type), pointer :: grid
  type(option_type), pointer :: option
  type(patch_type), pointer :: patch
  type(output_option_type), pointer :: output_option
  PetscInt :: i, j, k, nx, ny, nz
  PetscReal :: x, y, z
  PetscInt :: nxp1Xnyp1, nxp1, nyp1, nzp1
  PetscInt :: vertex_id
  PetscErrorCode :: ierr

1000 format(es13.6,1x,es13.6,1x,es13.6)
1001 format(i1,8(1x,i8))

  call PetscLogEventBegin(logging%event_output_grid_vtk,ierr);CHKERRQ(ierr)

  discretization => realization_base%discretization
  output_option => realization_base%output_option
  patch => realization_base%patch
  grid => patch%grid
  option => realization_base%option

  if (realization_base%discretization%itype == STRUCTURED_GRID)  then

    nx = grid%structured_grid%nx
    ny = grid%structured_grid%ny
    nz = grid%structured_grid%nz

    nxp1 = nx+1
    nyp1 = ny+1
    nzp1 = nz+1

    if (OptionIsIORank(option)) then

 1010 format("POINTS",1x,i12,1x,"float")
      write(fid,1010) (nx+1)*(ny+1)*(nz+1)
      do k=0,nz
        if (k > 0) then
          z = z + grid%structured_grid%dz_global(k)
        else
          z = discretization%origin_global(Z_DIRECTION)
        endif
        do j=0,ny
          if (j > 0) then
            y = y + grid%structured_grid%dy_global(j)
          else
            y = discretization%origin_global(Y_DIRECTION)
          endif
          x = discretization%origin_global(X_DIRECTION)
          write(fid,1000) x,y,z
          do i=1,nx
            x = x + grid%structured_grid%dx_global(i)
            write(fid,1000) x,y,z
          enddo
        enddo
      enddo

1020 format('CELLS',1x,i12,1x,i12)
      write(fid,1020) grid%nmax, grid%nmax*9
      nxp1Xnyp1 = nxp1*nyp1
      do k=0,nz-1
        do j=0,ny-1
          do i=0,nx-1
            vertex_id = i+j*nxp1+k*nxp1Xnyp1
            write(fid,1001) 8,vertex_id,vertex_id+1, &
                            vertex_id+nxp1+1,vertex_id+nxp1, &
                            vertex_id+nxp1Xnyp1,vertex_id+nxp1Xnyp1+1, &
                            vertex_id+nxp1Xnyp1+nxp1+1, &
                            vertex_id+nxp1Xnyp1+nxp1
          enddo
        enddo
      enddo

      write(fid,'(a)') ""

1030 format('CELL_TYPES',1x,i12)
      write(fid,1030) grid%nmax
      do i=1,grid%nmax
        write(fid,'(i2)') 12
      enddo

      write(fid,'(a)') ""

    endif
  else
    option%io_buffer = 'For unstructured grids, VTK formatted output lacks &
      &cell geometry information.'
    if (.not.output_option%vtk_acknowledgment) then
      option%io_buffer = trim(option%io_buffer) // &
        ' Please add ACKNOWLEDGE_VTK_FLAW to the OUTPUT block &
        &to acknowledge this defect, and the file will be printed.'
      call PrintErrMsg(option)
    endif
    call PrintWrnMsg(option)
  endif

  call PetscLogEventEnd(logging%event_output_grid_vtk,ierr);CHKERRQ(ierr)

end subroutine WriteVTKGrid

! ************************************************************************** !

subroutine WriteVTKDataSetFromVec(fid,realization_base,dataset_name,vec,datatype)
  !
  ! Writes data from a Petsc Vec within a block
  ! of a VTK file
  !

  use Realization_Base_class, only : realization_base_type

  implicit none

  PetscInt :: fid
  class(realization_base_type) :: realization_base
  Vec :: vec
  character(len=MAXWORDLENGTH) :: dataset_name
  PetscInt :: datatype
  PetscErrorCode :: ierr

  PetscReal, pointer :: vec_ptr(:)

  call VecGetArrayF90(vec,vec_ptr,ierr);CHKERRQ(ierr)
  call WriteVTKDataSet(fid,realization_base,dataset_name,vec_ptr,datatype, &
                       ZERO_INTEGER) ! 0 implies grid%nlmax
  call VecRestoreArrayF90(vec,vec_ptr,ierr);CHKERRQ(ierr)

end subroutine WriteVTKDataSetFromVec

! ************************************************************************** !

subroutine WriteVTKDataSet(fid,realization_base,dataset_name,array,datatype, &
                           size_flag)
  !
  ! Writes data from an array within a block
  ! of a VTK file
  !

  use Realization_Base_class, only : realization_base_type
  use Grid_module
  use Option_module
  use Patch_module

  implicit none

  PetscInt :: fid
  class(realization_base_type) :: realization_base
  PetscReal :: array(:)
  character(len=MAXWORDLENGTH) :: dataset_name
  PetscInt :: datatype
  PetscInt :: size_flag ! if size_flag /= 0, use size_flag as the local size

  type(grid_type), pointer :: grid
  type(option_type), pointer :: option
  type(patch_type), pointer :: patch
  PetscInt :: i
  PetscInt :: max_proc, max_proc_prefetch
  PetscMPIInt :: iproc_mpi, recv_size_mpi
  PetscInt :: max_local_size
  PetscMPIInt :: local_size_mpi
  PetscInt :: istart, iend, num_in_array
  PetscMPIInt :: status_mpi(MPI_STATUS_SIZE)
  PetscInt, allocatable :: integer_data(:), integer_data_recv(:)
  PetscReal, allocatable :: real_data(:), real_data_recv(:)
  PetscErrorCode :: ierr

1001 format(10(es13.6,1x))
1002 format(i3)

  patch => realization_base%patch
  grid => patch%grid
  option => realization_base%option

  call PetscLogEventBegin(logging%event_output_write_vtk,ierr);CHKERRQ(ierr)

  ! maximum number of initial messages
#define HANDSHAKE
  max_proc = option%io_handshake_buffer_size
  max_proc_prefetch = option%io_handshake_buffer_size / 10

  if (size_flag /= 0) then
    call MPI_Allreduce(size_flag,max_local_size,ONE_INTEGER_MPI,MPIU_INTEGER, &
                       MPI_MAX,option%mycomm,ierr);CHKERRQ(ierr)
    local_size_mpi = size_flag
  else
  ! if first time, determine the maximum size of any local array across
  ! all procs
    if (max_local_size_saved < 0) then
      call MPI_Allreduce(grid%nlmax,max_local_size,ONE_INTEGER_MPI, &
                         MPIU_INTEGER,MPI_MAX,option%mycomm, &
                         ierr);CHKERRQ(ierr)
      max_local_size_saved = max_local_size
      if (OptionPrintToScreen(option)) print *, 'max_local_size_saved: ', &
                                                 max_local_size
    endif
    max_local_size = max_local_size_saved
    local_size_mpi = grid%nlmax
  endif

  ! transfer the data to an integer or real array
  if (datatype == VTK_INTEGER) then
    allocate(integer_data(max_local_size+10))
    allocate(integer_data_recv(max_local_size))
    do i=1,local_size_mpi
      integer_data(i) = int(array(i))
    enddo
  else
    allocate(real_data(max_local_size+10))
    allocate(real_data_recv(max_local_size))
    do i=1,local_size_mpi
      real_data(i) = array(i)
    enddo
  endif

  ! communicate data to processor 0, round robin style
  if (OptionIsIORank(option)) then

    if (datatype == VTK_INTEGER) then
      write(fid,'(''SCALARS '',a20,'' int 1'')') dataset_name
    else
      write(fid,'(''SCALARS '',a20,'' float 1'')') dataset_name
    endif

    write(fid,'(''LOOKUP_TABLE default'')')

    if (datatype == VTK_INTEGER) then
      ! This approach makes output files identical, regardless of processor
      ! distribution.  It is necessary when diffing files.
      iend = 0
      do
        istart = iend+1
        if (iend+10 > local_size_mpi) exit
        iend = istart+9
        write(fid,1002) integer_data(istart:iend)
      enddo
      ! shift remaining data to front of array
      integer_data(1:local_size_mpi-iend) = integer_data(iend+1:local_size_mpi)
      num_in_array = local_size_mpi-iend
    else
      iend = 0
      do
        istart = iend+1
        if (iend+10 > local_size_mpi) exit
        iend = istart+9
        write(fid,1001) real_data(istart:iend)
      enddo
      ! shift remaining data to front of array
      real_data(1:local_size_mpi-iend) = real_data(iend+1:local_size_mpi)
      num_in_array = local_size_mpi-iend
    endif
    do iproc_mpi=1,option%comm%size-1
#ifdef HANDSHAKE
      if (option%io_handshake_buffer_size > 0 .and. &
          iproc_mpi+max_proc_prefetch >= max_proc) then
        max_proc = max_proc + option%io_handshake_buffer_size
        call MPI_Bcast(max_proc,ONE_INTEGER_MPI,MPIU_INTEGER, &
                       option%comm%io_rank,option%mycomm, &
                       ierr);CHKERRQ(ierr)
      endif
#endif
      call MPI_Probe(iproc_mpi,MPI_ANY_TAG,option%mycomm,status_mpi, &
                     ierr);CHKERRQ(ierr)
      recv_size_mpi = status_mpi(MPI_TAG)
      if (datatype == 0) then
        call MPI_Recv(integer_data_recv,recv_size_mpi,MPIU_INTEGER,iproc_mpi, &
                      MPI_ANY_TAG,option%mycomm,status_mpi, &
                      ierr);CHKERRQ(ierr)
        if (recv_size_mpi > 0) then
          integer_data(num_in_array+1:num_in_array+recv_size_mpi) = &
                                             integer_data_recv(1:recv_size_mpi)
          num_in_array = num_in_array+recv_size_mpi
        endif
        iend = 0
        do
          istart = iend+1
          if (iend+10 > num_in_array) exit
          iend = istart+9
          write(fid,1002) integer_data(istart:iend)
        enddo
        if (iend > 0) then
          integer_data(1:num_in_array-iend) = integer_data(iend+1:num_in_array)
          num_in_array = num_in_array-iend
        endif
      else
        call MPI_Recv(real_data_recv,recv_size_mpi,MPI_DOUBLE_PRECISION, &
                      iproc_mpi,MPI_ANY_TAG,option%mycomm,status_mpi, &
                      ierr);CHKERRQ(ierr)
        if (recv_size_mpi > 0) then
          real_data(num_in_array+1:num_in_array+recv_size_mpi) = &
                                             real_data_recv(1:recv_size_mpi)
          num_in_array = num_in_array+recv_size_mpi
        endif
        iend = 0
        do
          istart = iend+1
          if (iend+10 > num_in_array) exit
          iend = istart+9
          write(fid,1001) real_data(istart:iend)
        enddo
        if (iend > 0) then
          real_data(1:num_in_array-iend) = real_data(iend+1:num_in_array)
          num_in_array = num_in_array-iend
        endif
      endif
    enddo
#ifdef HANDSHAKE
    if (option%io_handshake_buffer_size > 0) then
      max_proc = -1
      call MPI_Bcast(max_proc,ONE_INTEGER_MPI,MPIU_INTEGER, &
                     option%comm%io_rank,option%mycomm,ierr);CHKERRQ(ierr)
    endif
#endif
    ! Print the remaining values, if they exist
    if (datatype == 0) then
      if (num_in_array > 0) &
        write(fid,1002) integer_data(1:num_in_array)
    else
      if (num_in_array > 0) &
        write(fid,1001) real_data(1:num_in_array)
    endif
    write(fid,'(/)')
  else
#ifdef HANDSHAKE
    if (option%io_handshake_buffer_size > 0) then
      do
        if (option%myrank < max_proc) exit
        call MPI_Bcast(max_proc,ONE_INTEGER_MPI,MPIU_INTEGER, &
                       option%comm%io_rank,option%mycomm, &
                       ierr);CHKERRQ(ierr)
      enddo
    endif
#endif
    if (datatype == VTK_INTEGER) then
      call MPI_Send(integer_data,local_size_mpi,MPIU_INTEGER, &
                    option%comm%io_rank,local_size_mpi,option%mycomm, &
                    ierr);CHKERRQ(ierr)
    else
      call MPI_Send(real_data,local_size_mpi,MPI_DOUBLE_PRECISION, &
                    option%comm%io_rank,local_size_mpi,option%mycomm, &
                    ierr);CHKERRQ(ierr)
    endif
#ifdef HANDSHAKE
    if (option%io_handshake_buffer_size > 0) then
      do
        call MPI_Bcast(max_proc,ONE_INTEGER_MPI,MPIU_INTEGER, &
                       option%comm%io_rank,option%mycomm, &
                       ierr);CHKERRQ(ierr)
        if (max_proc < 0) exit
      enddo
    endif
#endif
#undef HANDSHAKE
  endif

  if (datatype == VTK_INTEGER) then
    deallocate(integer_data)
  else
    deallocate(real_data)
  endif

  call PetscLogEventEnd(logging%event_output_write_vtk,ierr);CHKERRQ(ierr)

end subroutine WriteVTKDataSet

end module Output_VTK_module
