module Convergence_module

#include "petsc/finclude/petscsnes.h"
  use petscsnes
  use Solver_module
  use Option_module
  use Grid_module

  use PFLOTRAN_Constants_module

  implicit none

  private

  type, public :: convergence_context_type
    type(solver_type), pointer :: solver
    type(option_type), pointer :: option
    type(grid_type), pointer :: grid
  end type convergence_context_type


  public :: ConvergenceContextCreate, ConvergenceTest, &
            ConvergenceContextDestroy

contains

! ************************************************************************** !

function ConvergenceContextCreate(solver,option,grid)
  !
  ! Creates a context containing pointer
  ! for convergence subroutines
  !
  ! Author: Glenn Hammond
  ! Date: 02/12/08
  !

  implicit none

  type(convergence_context_type), pointer :: ConvergenceContextCreate
  type(solver_type), pointer :: solver
  type(option_type), pointer :: option
  type(grid_type), pointer :: grid

  type(convergence_context_type), pointer :: context

  allocate(context)
  context%solver => solver
  context%option => option
  context%grid => grid

  ConvergenceContextCreate => context

end function ConvergenceContextCreate

! ************************************************************************** !

subroutine ConvergenceTest(snes_,i_iteration,xnorm,unorm,fnorm,reason, &
                           grid,option,solver,ierr)
  !
  ! User defined convergence test
  !
  ! Author: Glenn Hammond
  ! Date: 02/12/08
  !
  use String_module

  implicit none

  SNES :: snes_
  PetscInt :: i_iteration
  PetscReal :: xnorm ! 2-norm of updated solution
  PetscReal :: unorm ! 2-norm of update. PETSc refers to this as snorm
  PetscReal :: fnorm ! 2-norm of updated residual
  SNESConvergedReason :: reason
  PetscErrorCode :: ierr
  type(solver_type) :: solver
  type(option_type) :: option
  !TODO(geh): remove calculations based on grid to something for pm specific
  type(grid_type), pointer :: grid

  Vec :: solution_vec
  Vec :: update_vec
  Vec :: residual_vec
  PetscReal :: inorm_solution  !infinity norms
  PetscReal :: inorm_update
  PetscReal :: inorm_residual

  PetscInt :: i, ndof
  PetscInt :: icount
  PetscReal, allocatable :: fnorm_solution_stride(:)
  PetscReal, allocatable :: fnorm_update_stride(:)
  PetscReal, allocatable :: fnorm_residual_stride(:)
  PetscReal, allocatable :: inorm_solution_stride(:)
  PetscReal, allocatable :: inorm_update_stride(:)
  PetscReal, allocatable :: inorm_residual_stride(:)

  PetscReal :: norm1_solution
  PetscReal :: norm1_update
  PetscReal :: norm1_residual
  PetscReal, allocatable :: norm1_solution_stride(:)
  PetscReal, allocatable :: norm1_update_stride(:)
  PetscReal, allocatable :: norm1_residual_stride(:)

  KSP :: ksp

  PetscInt, allocatable :: imax_solution(:)
  PetscInt, allocatable :: imax_update(:)
  PetscInt, allocatable :: imax_residual(:)
  PetscReal, allocatable :: max_solution_val(:)
  PetscReal, allocatable :: max_update_val(:)
  PetscReal, allocatable :: max_residual_val(:)

  PetscInt, allocatable :: imin_solution(:)
  PetscInt, allocatable :: imin_update(:)
  PetscInt, allocatable :: imin_residual(:)
  PetscReal, allocatable :: min_solution_val(:)
  PetscReal, allocatable :: min_update_val(:)
  PetscReal, allocatable :: min_residual_val(:)

  character(len=MAXSTRINGLENGTH) :: string, sec_string
  character(len=MAXSTRINGLENGTH) :: rsn_string
  character(len=MAXSTRINGLENGTH) :: out_string
  PetscBool :: print_sol_norm_info = PETSC_FALSE
  PetscBool :: print_upd_norm_info = PETSC_FALSE
  PetscBool :: print_res_norm_info = PETSC_FALSE
  PetscBool :: print_norm_by_dof_info = PETSC_FALSE
  PetscBool :: print_max_val_and_loc_info = PETSC_FALSE
  PetscBool :: print_1_norm_info = PETSC_FALSE
  PetscBool :: print_2_norm_info = PETSC_FALSE
  PetscBool :: print_inf_norm_info = PETSC_FALSE

  PetscInt :: sec_reason

! From PETSC_DIR/include/petscsnes.h
!typedef enum {/* converged */
!              SNES_CONVERGED_FNORM_ABS         =  2, /* ||F|| < atol */
!              SNES_CONVERGED_FNORM_RELATIVE    =  3, /* ||F|| < rtol*||F_initial|| */
!              SNES_CONVERGED_SNORM_RELATIVE    =  4, /* Newton computed step size small; || delta x || < stol || x ||*/
!              SNES_CONVERGED_ITS               =  5, /* maximum iterations reached */
!              SNES_CONVERGED_TR_DELTA          =  7,
!              SNES_BREAKOUT_INNER_ITER         =  6, /* Flag to break out of inner loop after checking custom convergence. */
!                                                     /* it is used in multi-phase flow when state changes */
!              /* diverged */
!              SNES_DIVERGED_FUNCTION_DOMAIN     = -1, /* the new x location passed the function is not in the domain of F */
!              SNES_DIVERGED_FUNCTION_COUNT      = -2,
!              SNES_DIVERGED_LINEAR_SOLVE        = -3, /* the linear solve failed */
!              SNES_DIVERGED_FNORM_NAN           = -4,
!              SNES_DIVERGED_MAX_IT              = -5,
!              SNES_DIVERGED_LINE_SEARCH         = -6, /* the line search failed */
!              SNES_DIVERGED_INNER               = -7, /* inner solve failed */
!              SNES_DIVERGED_LOCAL_MIN           = -8, /* || J^T b || is small, implies converged to local minimum of F() */
!              SNES_DIVERGED_DTOL                = -9, /* || F || > divtol*||F_initial|| */
!              SNES_DIVERGED_JACOBIAN_DOMAIN     = -10, /* Jacobian calculation does not make sense */
!              SNES_DIVERGED_TR_DELTA            = -11,
!              SNES_CONVERGED_TR_DELTA_DEPRECATED = -11,
!              SNES_CONVERGED_ITERATING          =  0} SNESConvergedReason;
!PETSC_EXTERN const char *const*SNESConvergedReasons;
  sec_reason = 0

  if (option%use_touch_options) then
    string = 'detailed_convergence'
    if (OptionCheckTouch(option,string)) then
      if (solver%print_detailed_convergence) then
        solver%print_detailed_convergence = PETSC_FALSE
      else
        solver%print_detailed_convergence = PETSC_TRUE
      endif
    endif
  endif

  !geh: We must check the convergence here as i_iteration initializes
  !     snes->ttol for subsequent iterations.
  call SNESConvergedDefault(snes_,i_iteration,xnorm,unorm,fnorm,reason, &
                            0,ierr);CHKERRQ(ierr)

  if (option%convergence /= CONVERGENCE_CONVERGED .and. reason == -9) then
    write(out_string,'(i3," 2r:",es9.2," 2x:",es9.2," 2u:",es9.2, &
          & " -diverged")') i_iteration, fnorm, xnorm, unorm
    call PrintMsg(option,out_string)
    return
  endif

#if 0
  if (i_iteration == 0 .and. &
      option%print_screen_flag .and. solver%print_convergence) then
    write(*,'(i3," 2r:",es9.2)') i_iteration, fnorm
  endif
#endif

  ! for some reason (e.g. negative saturation/mole fraction in multiphase),
  ! we are forcing extra newton iterations
  if (option%force_newton_iteration) then
   reason = 0
!   reason = -1
   return
  endif

! Checking if norm exceeds divergence tolerance
!geh: inorm_residual is being used without being calculated.
!      if (fnorm > solver%max_norm .or. unorm > solver%max_norm .or. &
!        inorm_residual > solver%max_norm) then

  if (option%out_of_table) then
    reason = -19
  endif

  if (option%converged) then
    reason = 12
    ! set back to false
    option%converged = PETSC_FALSE
  endif

  if (option%convergence /= CONVERGENCE_OFF) then
    select case(option%convergence)
      case(CONVERGENCE_CUT_TIMESTEP)
        reason = -88
      case(CONVERGENCE_KEEP_ITERATING)
        reason = 0
      case(CONVERGENCE_FORCE_ITERATION)
        reason = 0
      case(CONVERGENCE_CONVERGED)
        reason = 999
      case(CONVERGENCE_BREAKOUT_INNER_ITER)
        reason = 6
    end select
  endif
  ! must turn off after each convergence check as a subsequent process
  ! model may not use this custom test
  option%convergence = CONVERGENCE_OFF

!  if (reason <= 0 .and. solver%check_infinity_norm) then
  if (solver%check_infinity_norm) then

    call SNESGetFunction(snes_,residual_vec,PETSC_NULL_FUNCTION, &
                         PETSC_NULL_INTEGER,ierr);CHKERRQ(ierr)

    call VecNorm(residual_vec,NORM_INFINITY,inorm_residual, &
                 ierr);CHKERRQ(ierr)

    if (i_iteration > 0) then
      call SNESGetSolutionUpdate(snes_,update_vec,ierr);CHKERRQ(ierr)
      call VecNorm(update_vec,NORM_INFINITY,inorm_update,ierr);CHKERRQ(ierr)
    else
      inorm_update = 0.d0
    endif

    if (inorm_residual < solver%newton_inf_res_tol) then
      reason = 10
    else
!      if (reason > 0 .and. inorm_residual > 100.d0*solver%newton_inf_res_tol) &
!        reason = 0
    endif

    if (inorm_update < solver%newton_inf_upd_tol .and. i_iteration > 0) then
      reason = 11
    endif

    if (inorm_residual > solver%max_norm) then
      reason = -20
    endif

    ! This is to check if the secondary continuum residual convergences
    ! for nonlinear problems specifically transport
    !TODO(geh): move to PMRTCheckConvergence
    if (solver%itype == TRANSPORT_CLASS .and. option%use_sc .and. &
       reason > 0 .and. i_iteration > 0) then
      if (option%infnorm_res_sec < solver%newton_inf_res_tol_sec) then
        sec_reason = 1
      else
        reason = 0
      endif
    endif

    ! force the minimum number of iterations
    if (i_iteration < solver%newton_min_iterations .and. reason /= -88) then
        reason = 0
    endif

    if (solver%print_convergence) then
      i = int(reason)
      select case(i)
        case(-20)
          rsn_string = 'max_norm'
        case(-19)
          rsn_string = 'out_of_EOS_table'
        case(2)
          rsn_string = 'atol'
        case(3)
          rsn_string = 'rtol'
        case(4)
          rsn_string = 'stol'
        case(10)
          rsn_string = 'itol_res'
        case(11)
          rsn_string = 'itol_upd'
        case(12)
          rsn_string = 'itol_post_check'
        case default
          write(rsn_string,'(i3)') reason
      end select
      if (option%use_sc .and. option%ntrandof > 0 .and. solver%itype == &
          TRANSPORT_CLASS) then
        i = int(sec_reason)
        select case(i)
          case(1)
            sec_string = 'itol_res_sec'
          case default
            write(sec_string,'(i3)') sec_reason
        end select
        write(out_string,&
             '(i3," 2r:",es9.2, &
                & " 2x:",es9.2, &
                & " 2u:",es9.2, &
                & " ir:",es9.2, &
                & " iu:",es9.2, &
                & " irsec:",es9.2, &
                & " rsn: ",a, ", ",a)') &
                i_iteration, fnorm, xnorm, unorm, inorm_residual, &
                inorm_update, option%infnorm_res_sec, &
                trim(rsn_string), trim(sec_string)
      else
        write(out_string,'(i3)') i_iteration
        icount = 5
        if (solver%convergence_2r) then
          out_string = trim(out_string) // ' 2r: ' // &
            StringWrite('(es9.2)',fnorm)
          icount = icount - 1
        endif
        if (solver%convergence_2x) then
          out_string = trim(out_string) // ' 2x: ' // &
            StringWrite('(es9.2)',xnorm)
          icount = icount - 1
        endif
        if (solver%convergence_2u) then
          out_string = trim(out_string) // ' 2u: ' // &
            StringWrite('(es9.2)',unorm)
          icount = icount - 1
        endif
        if (solver%convergence_ir) then
          out_string = trim(out_string) // ' ir: ' // &
            StringWrite('(es9.2)',inorm_residual)
          icount = icount - 1
        endif
        if (solver%convergence_2u) then
          out_string = trim(out_string) // ' iu: ' // &
            StringWrite('(es9.2)',inorm_update)
          icount = icount - 1
        endif
        if (icount > 0) then
          icount = icount - 1
          string = '("'//trim(out_string)//'",'
          if (icount > 0) then
            string = trim(string) // &
                     trim(StringWrite(icount*13)) // 'x,'
          endif
          string = trim(string) // '" rsn: '//trim(rsn_string)//'")'
          write(out_string,trim(string))
        else
          out_string = trim(out_string) // ' rsn: ' // trim(rsn_string)
        endif
      endif
      call PrintMsg(option,out_string)
    endif
  else

    ! This is to check if the secondary continuum residual convergences
    ! for nonlinear problems specifically transport
    if (solver%itype == TRANSPORT_CLASS .and. option%use_sc .and. &
       reason > 0 .and. i_iteration > 0) then
      if (option%infnorm_res_sec < solver%newton_inf_res_tol_sec) then
        reason = 13
      else
        reason = 0
      endif
    endif

    ! force the minimum number of iterations
    if (i_iteration < solver%newton_min_iterations .and. reason /= -88) then
      reason = 0
    endif

    if (solver%print_convergence) then
      i = int(reason)
      select case(i)
        case(-19)
          string = 'out_of_EOS_table'
        case(2)
          string = 'atol'
        case(3)
          string = 'rtol'
        case(4)
          string = 'stol'
        case(10)
          string = 'itol_res'
        case(11)
          string = 'itol_upd'
        case(12)
          string = 'itol_post_check'
        case(13)
          string = 'itol_res_sec'
        case default
          write(string,'(i3)') reason
      end select
      write(out_string,'(i3," 2r:",es10.2, &
                          & " 2u:",es10.2, &
                          & 32x, &
                      & " rsn: ",a)') i_iteration, fnorm, unorm, trim(string)
      call PrintMsg(option,out_string)
      if (solver%print_linear_iterations) then
        call KSPGetIterationNumber(solver%ksp,i,ierr);CHKERRQ(ierr)
        write(option%io_buffer,'("   Linear Solver Iterations: ",i6)') i
        call PrintMsg(option)
      endif
    endif
  endif

  if (solver%print_detailed_convergence .and. associated(grid)) then

    call SNESGetSolution(snes_,solution_vec,ierr);CHKERRQ(ierr)
    ! the ctx object should really be PETSC_NULL_OBJECT.  A bug in petsc
    call SNESGetFunction(snes_,residual_vec,PETSC_NULL_FUNCTION, &
                         PETSC_NULL_INTEGER,ierr);CHKERRQ(ierr)
    call SNESGetSolutionUpdate(snes_,update_vec,ierr);CHKERRQ(ierr)

    ! infinity norms
    call VecNorm(solution_vec,NORM_INFINITY,inorm_solution, &
                 ierr);CHKERRQ(ierr)
    call VecNorm(update_vec,NORM_INFINITY,inorm_update,ierr);CHKERRQ(ierr)
    call VecNorm(residual_vec,NORM_INFINITY,inorm_residual, &
                 ierr);CHKERRQ(ierr)

    call VecNorm(solution_vec,NORM_1,norm1_solution,ierr);CHKERRQ(ierr)
    call VecNorm(update_vec,NORM_1,norm1_update,ierr);CHKERRQ(ierr)
    call VecNorm(residual_vec,NORM_1,norm1_residual,ierr);CHKERRQ(ierr)

    call VecGetBlockSize(solution_vec,ndof,ierr);CHKERRQ(ierr)

    allocate(fnorm_solution_stride(ndof))
    allocate(fnorm_update_stride(ndof))
    allocate(fnorm_residual_stride(ndof))
    allocate(inorm_solution_stride(ndof))
    allocate(inorm_update_stride(ndof))
    allocate(inorm_residual_stride(ndof))
    allocate(norm1_solution_stride(ndof))
    allocate(norm1_update_stride(ndof))
    allocate(norm1_residual_stride(ndof))

    allocate(imax_solution(ndof))
    allocate(imax_update(ndof))
    allocate(imax_residual(ndof))
    allocate(max_solution_val(ndof))
    allocate(max_update_val(ndof))
    allocate(max_residual_val(ndof))

    allocate(imin_solution(ndof))
    allocate(imin_update(ndof))
    allocate(imin_residual(ndof))
    allocate(min_solution_val(ndof))
    allocate(min_update_val(ndof))
    allocate(min_residual_val(ndof))

    call VecStrideNormAll(solution_vec,NORM_1,norm1_solution_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(update_vec,NORM_1,norm1_update_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(residual_vec,NORM_1,norm1_residual_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(solution_vec,NORM_2,fnorm_solution_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(update_vec,NORM_2,fnorm_update_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(residual_vec,NORM_2,fnorm_residual_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(solution_vec,NORM_INFINITY,inorm_solution_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(update_vec,NORM_INFINITY,inorm_update_stride, &
                          ierr);CHKERRQ(ierr)
    call VecStrideNormAll(residual_vec,NORM_INFINITY,inorm_residual_stride, &
                          ierr);CHKERRQ(ierr)

    ! can't use VecStrideMaxAll since the index location is not currently supported.
    do i=1,ndof
      call VecStrideMax(solution_vec,i-1,imax_solution(i),max_solution_val(i), &
                        ierr);CHKERRQ(ierr)
      call VecStrideMax(update_vec,i-1,imax_update(i),max_update_val(i), &
                        ierr);CHKERRQ(ierr)
      call VecStrideMax(residual_vec,i-1,imax_residual(i),max_residual_val(i), &
                        ierr);CHKERRQ(ierr)
      ! tweak the index to get the cell id from the mdof vector
      imax_solution(i) = GridIndexToCellID(solution_vec,imax_solution(i),grid,GLOBAL)
      imax_update(i) = GridIndexToCellID(update_vec,imax_update(i),grid,GLOBAL)
      imax_residual(i) = GridIndexToCellID(residual_vec,imax_residual(i),grid,GLOBAL)
!      imax_solution(i) = imax_solution(i)/ndof
!      imax_update(i) = imax_update(i)/ndof
!      imax_residual(i) = imax_residual(i)/ndof
    enddo

    do i=1,ndof
      call VecStrideMin(solution_vec,i-1,imin_solution(i),min_solution_val(i), &
                        ierr);CHKERRQ(ierr)
      call VecStrideMin(update_vec,i-1,imin_update(i),min_update_val(i), &
                        ierr);CHKERRQ(ierr)
      call VecStrideMin(residual_vec,i-1,imin_residual(i),min_residual_val(i), &
                        ierr);CHKERRQ(ierr)
      ! tweak the index to get the cell id from the mdof vector
      imin_solution(i) = GridIndexToCellID(solution_vec,imin_solution(i),grid,GLOBAL)
      imin_update(i) = GridIndexToCellID(update_vec,imax_update(i),grid,GLOBAL)
      imin_residual(i) = GridIndexToCellID(residual_vec,imin_residual(i),grid,GLOBAL)
!      imin_solution(i) = imin_solution(i)/ndof
!      imin_update(i) = imin_update(i)/ndof
!      imin_residual(i) = imin_residual(i)/ndof
    enddo

    if (OptionPrintToScreen(option)) then
      select case(reason)
        case (10)
          string = "CONVERGED_USER_NORM_INF_REL"
        case (11)
          string = "CONVERGED_USER_NORM_INF_UPD"
        case(SNES_CONVERGED_FNORM_ABS)
          string = "SNES_CONVERGED_FNORM_ABS"
        case(SNES_CONVERGED_FNORM_RELATIVE)
          string = "SNES_CONVERGED_FNORM_RELATIVE"
        case(SNES_CONVERGED_SNORM_RELATIVE)
          string = "SNES_CONVERGED_SNORM_RELATIVE"
        case(SNES_CONVERGED_ITS)
          string = "SNES_CONVERGED_ITS"
        case(6)
          string = "SNES_BREAKOUT_INNER_ITER"
        case(SNES_DIVERGED_TR_DELTA)
          string = "SNES_DIVERGED_TR_DELTA"
  !      case(SNES_DIVERGED_FUNCTION_DOMAIN)
  !        string = "SNES_DIVERGED_FUNCTION_DOMAIN"
        case(SNES_DIVERGED_FUNCTION_COUNT)
          string = "SNES_DIVERGED_FUNCTION_COUNT"
        case(SNES_DIVERGED_LINEAR_SOLVE)
          string = "SNES_DIVERGED_LINEAR_SOLVE"
        case(SNES_DIVERGED_FNORM_NAN)
          string = "SNES_DIVERGED_FNORM_NAN"
        case(SNES_DIVERGED_MAX_IT)
          string = "SNES_DIVERGED_MAX_IT"
        case(SNES_DIVERGED_LINE_SEARCH)
          string = "SNES_DIVERGED_LINE_SEARCH"
        case(SNES_DIVERGED_LOCAL_MIN)
          string = "SNES_DIVERGED_LOCAL_MIN"
        case(SNES_CONVERGED_ITERATING)
          string = "SNES_CONVERGED_ITERATING"
        case default
          string = "UNKNOWN"
      end select

      ! uncomment the lines below to determine data printed

      print_sol_norm_info = PETSC_TRUE  ! solution_vec norm information
      print_upd_norm_info = PETSC_TRUE  ! update_vec norm information
      print_res_norm_info = PETSC_TRUE  ! residual_vec norm information

      !print_norm_by_dof_info = PETSC_TRUE
      print_max_val_and_loc_info = PETSC_TRUE

      !print_1_norm_info = PETSC_TRUE
      print_2_norm_info = PETSC_TRUE
      print_inf_norm_info = PETSC_TRUE

      print *
      print *, 'reason: ', reason, ' - ', trim(string)
      print *, 'SNES iteration :', i_iteration
      call SNESGetKSP(snes_,ksp,ierr);CHKERRQ(ierr)
      call KSPGetIterationNumber(ksp,i,ierr);CHKERRQ(ierr)
      print *, 'KSP iterations :', i
      if (print_1_norm_info) then
        if (print_sol_norm_info) print *, 'norm_1_solution:   ', norm1_solution
        if (print_upd_norm_info) print *, 'norm_1_update:     ', norm1_update
        if (print_res_norm_info) print *, 'norm_1_residual:   ', norm1_residual
      endif
      if (print_2_norm_info) then
        if (print_sol_norm_info) print *, 'norm_2_solution:   ', fnorm_solution_stride
        if (print_upd_norm_info) print *, 'norm_2_update:     ', fnorm_update_stride
        if (print_res_norm_info) print *, 'norm_2_residual:   ', fnorm_residual_stride
      endif
      if (print_inf_norm_info) then
        if (print_sol_norm_info) print *, 'norm_inf_solution: ', inorm_solution
        if (print_upd_norm_info) print *, 'norm_inf_update:   ', inorm_update
        if (print_res_norm_info) print *, 'norm_inf_residual: ', inorm_residual
      endif
      if (print_max_val_and_loc_info) then
        print *, 'max/min locations (zero-based index) by dof:'
        do i=1,ndof
          print *, '  dof: ', i
          if (print_sol_norm_info) then
            print *, '    solution_vec max: ', imax_solution(i), max_solution_val(i)
            print *, '    solution_vec min: ', imin_solution(i), min_solution_val(i)
          endif
          if (print_upd_norm_info) then ! since update is -dx, need to invert
            print *, '    update_vec max:   ', imin_update(i), -min_update_val(i)
            print *, '    update_vec min:   ', imax_update(i), -max_update_val(i)
          endif
          if (print_res_norm_info) then
            print *, '    residual_vec max: ', imax_residual(i), max_residual_val(i)
            print *, '    residual_vec min: ', imin_residual(i), min_residual_val(i)
          endif
        enddo
      endif
      if (print_norm_by_dof_info) then
        print *, 'norm by dof:'
        do i=1,ndof
          print *, '  dof: ', i
          if (print_sol_norm_info) then
            if (print_1_norm_info) &
              print *, '    norm_1_solution:   ', norm1_solution_stride(i)
            if (print_2_norm_info) &
              print *, '    norm_2_solution:   ', fnorm_solution_stride(i)
            if (print_inf_norm_info) &
              print *, '    norm_inf_solution: ', inorm_solution_stride(i)
            if (print_1_norm_info .or. print_2_norm_info .or. &
                print_inf_norm_info) print *, '    -'
          endif
          if (print_upd_norm_info) then
            if (print_1_norm_info) &
              print *, '    norm_1_update:   ', norm1_update_stride(i)
            if (print_2_norm_info) &
              print *, '    norm_2_update:   ', fnorm_update_stride(i)
            if (print_inf_norm_info) &
              print *, '    norm_inf_update: ', inorm_update_stride(i)
            if (print_1_norm_info .or. print_2_norm_info .or. &
                print_inf_norm_info) print *, '    -'
          endif
          if (print_res_norm_info) then
            if (print_1_norm_info) &
              print *, '    norm_1_residual:   ', norm1_residual_stride(i)
            if (print_2_norm_info) &
              print *, '    norm_2_residual:   ', fnorm_residual_stride(i)
            if (print_inf_norm_info) &
              print *, '    norm_inf_residual: ', inorm_residual_stride(i)
          endif
        enddo
      endif
      print *
    endif

    deallocate(fnorm_solution_stride)
    deallocate(fnorm_update_stride)
    deallocate(fnorm_residual_stride)
    deallocate(inorm_solution_stride)
    deallocate(inorm_update_stride)
    deallocate(inorm_residual_stride)
    deallocate(norm1_solution_stride)
    deallocate(norm1_update_stride)
    deallocate(norm1_residual_stride)

    deallocate(imax_solution)
    deallocate(imax_update)
    deallocate(imax_residual)
    deallocate(max_solution_val)
    deallocate(max_update_val)
    deallocate(max_residual_val)

    deallocate(imin_solution)
    deallocate(imin_update)
    deallocate(imin_residual)
    deallocate(min_solution_val)
    deallocate(min_update_val)
    deallocate(min_residual_val)

  endif

end subroutine ConvergenceTest

! ************************************************************************** !

subroutine ConvergenceContextDestroy(context)
  !
  ! Destroy context
  !
  ! Author: Glenn Hammond
  ! Date: 02/12/08
  !

  implicit none

  type(convergence_context_type), pointer :: context

  if (.not.associated(context)) return

  nullify(context%solver)
  nullify(context%option)
  nullify(context%grid)

  deallocate(context)
  nullify(context)

end subroutine ConvergenceContextDestroy

end module Convergence_module
