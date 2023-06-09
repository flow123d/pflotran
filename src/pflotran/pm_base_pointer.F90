module PM_Base_Pointer_module

#include "petsc/finclude/petscts.h"
  use petscts
  use PM_Base_class

  use PFLOTRAN_Constants_module

  implicit none

  private

  ! Since the context (ctx) for procedures passed to PETSc must be declared
  ! as a "type" instead of a "class", object is a workaround for passing the
  ! process model as context of a procedure where one can pass the
  ! pm_base_pointer_type to a procedure, declaring it as e.g.
  !
  ! type(pm_base_pointer_type) :: pm_ptr
  !
  ! and use the ptr:
  !
  ! pm_ptr%this%Residual
  !
  type, public :: pm_base_pointer_type
    class(pm_base_type), pointer :: pm
  end type pm_base_pointer_type

  public :: PMResidualPtr, &
            PMJacobianPtr, &
            PMCheckUpdatePreTRPtr, &
            PMCheckUpdatePostTRPtr, &
            PMCheckUpdatePrePtr, &
            PMCheckUpdatePostPtr, &
            PMCheckConvergencePtr, &
            PMRHSFunctionPtr, &
            PMIFunctionPtr, &
            PMIJacobianPtr

contains

! ************************************************************************** !

subroutine PMResidualPtr(snes,xx,r,this,ierr)
  !
  ! Author: Glenn Hammond
  ! Date: 03/14/13
  !
  implicit none

  SNES :: snes
  Vec :: xx
  Vec :: r
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  call this%pm%Residual(snes,xx,r,ierr)

end subroutine PMResidualPtr

! ************************************************************************** !

subroutine PMJacobianPtr(snes,xx,A,B,this,ierr)
  !
  ! Author: Glenn Hammond
  ! Date: 03/14/13
  !
  implicit none

  SNES :: snes
  Vec :: xx
  Mat :: A, B
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  call this%pm%Jacobian(snes,xx,A,B,ierr)

end subroutine PMJacobianPtr

! ************************************************************************** !

subroutine PMRHSFunctionPtr(ts,time,xx,ff,this,ierr)
  !
  ! Author: Gautam Bisht
  ! Date: 04/12/13
  !
  implicit none

  TS :: ts
  PetscReal :: time
  Vec :: xx
  Vec :: ff
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  call this%pm%RHSFunction(ts,time,xx,ff,ierr)

end subroutine PMRHSFunctionPtr

! ************************************************************************** !

subroutine PMIFunctionPtr(ts,time,U,Udot,F,this,ierr)
  !
  ! Author: Gautam Bisht
  ! Date: 06/20/18
  !
  implicit none

  TS :: ts
  PetscReal :: time
  Vec :: U, Udot
  Vec :: F
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  call this%pm%IFunction(ts,time,U,Udot,F,ierr)

end subroutine PMIFunctionPtr

! ************************************************************************** !

subroutine PMIJacobianPtr(ts,time,U,Udot,shift,A,B,this,ierr)
  !
  ! Author: Gautam Bisht
  ! Date: 06/20/18
  !
  implicit none

  TS :: ts
  PetscReal :: time
  Vec :: U, Udot
  PetscReal :: shift
  Mat :: A, B
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  call this%pm%IJacobian(ts,time,U,Udot,shift,A,B,ierr)

end subroutine PMIJacobianPtr

! ************************************************************************** !

subroutine PMCheckUpdatePreTRPtr(snes,X,dX,changed,this,ierr)
  !
  ! Wrapper for native call to XXXCheckUpdatePreTR
  ! when using Newton Trust Region Method
  !
  ! Author: Heeho Park
  ! Date: 04/13/20
  !
   implicit none

  Vec :: X
  Vec :: dX
  PetscBool :: changed
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  SNES :: snes

  call this%pm%CheckUpdatePre(snes,X,dX,changed,ierr)

end subroutine PMCheckUpdatePreTRPtr

! ************************************************************************** !

subroutine PMCheckUpdatePostTRPtr(snes,X0,dX,X1,dX_changed,X1_changed, &
                                this,ierr)
  !
  ! Wrapper for native call to XXXCheckUpdatePost
  ! when using Newton Trust Region Method
  !
  ! Author: Heeho Park
  ! Date: 04/13/20
  !
  implicit none

  Vec :: X0
  Vec :: dX
  Vec :: X1
  PetscBool :: dX_changed
  PetscBool :: X1_changed
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  SNES :: snes

  call this%pm%CheckUpdatePost(snes,X0,dX,X1,dX_changed,X1_changed,ierr)

end subroutine PMCheckUpdatePostTRPtr

! ************************************************************************** !

subroutine PMCheckUpdatePrePtr(linesearch,X,dX,changed,this,ierr)
  !
  ! Wrapper for native call to XXXCheckUpdatePre
  !
  ! Author: Glenn Hammond
  ! Date: 12/02/14
  !
   implicit none

  SNESLineSearch :: linesearch
  Vec :: X
  Vec :: dX
  PetscBool :: changed
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  SNES :: snes

  call SNESLineSearchGetSNES(linesearch,snes,ierr);CHKERRQ(ierr)
  call this%pm%CheckUpdatePre(snes,X,dX,changed,ierr)

end subroutine PMCheckUpdatePrePtr

! ************************************************************************** !

subroutine PMCheckUpdatePostPtr(linesearch,X0,dX,X1,dX_changed,X1_changed, &
                                this,ierr)
  !
  ! Wrapper for native call to XXXCheckUpdatePost
  !
  ! Author: Glenn Hammond
  ! Date: 12/02/14
  !
  implicit none

  SNESLineSearch :: linesearch
  Vec :: X0
  Vec :: dX
  Vec :: X1
  PetscBool :: dX_changed
  PetscBool :: X1_changed
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  SNES :: snes

  call SNESLineSearchGetSNES(linesearch,snes,ierr);CHKERRQ(ierr)
  call this%pm%CheckUpdatePost(snes,X0,dX,X1,dX_changed,X1_changed,ierr)

end subroutine PMCheckUpdatePostPtr

! ************************************************************************** !

subroutine PMCheckConvergencePtr(snes,it,xnorm,unorm,fnorm,reason,this,ierr)
  !
  ! User defined convergence test for a process model
  !
  ! Author: Glenn Hammond
  ! Date: 11/15/17
  !
  implicit none

  SNES :: snes
  PetscInt :: it
  PetscReal :: xnorm ! 2-norm of updated solution
  PetscReal :: unorm ! 2-norm of update. PETSc refers to this as snorm
  PetscReal :: fnorm ! 2-norm of updated residual
  SNESConvergedReason :: reason
  type(pm_base_pointer_type) :: this
  PetscErrorCode :: ierr

  call this%pm%CheckConvergence(snes,it,xnorm,unorm,fnorm,reason,ierr)

end subroutine PMCheckConvergencePtr

end module PM_Base_Pointer_module
