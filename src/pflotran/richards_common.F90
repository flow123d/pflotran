module Richards_Common_module

#include "petsc/finclude/petscsnes.h"
  use petscsnes
  use Richards_Aux_module
  use Global_Aux_module

  use PFLOTRAN_Constants_module
  use Utility_module, only : Equal

  implicit none

  private

! Cutoff parameters
  PetscReal, parameter :: eps       = 1.D-8
  PetscReal, parameter :: floweps   = 1.D-24
  PetscReal, parameter :: perturbation_tolerance = 1.d-6

  public RichardsAccumulation, &
         RichardsAccumDerivative, &
         RichardsFlux, &
         RichardsFluxDerivative, &
         RichardsBCFlux, &
         RichardsBCFluxDerivative

contains

! ************************************************************************** !

subroutine RichardsAccumDerivative(rich_auxvar,global_auxvar, &
                                   material_auxvar, &
                                   option, &
                                   characteristic_curves, &
                                   J)
  !
  ! Computes derivatives of the accumulation
  ! term for the Jacobian
  !
  ! Author: Glenn Hammond
  ! Date: 12/13/07
  !

  use Option_module
  use Characteristic_Curves_module
  use Material_Aux_module, only : material_auxvar_type, &
                                 MaterialAuxVarInit, &
                                 MaterialAuxVarCopy, &
                                 MaterialAuxVarStrip

  implicit none

  type(richards_auxvar_type) :: rich_auxvar
  type(global_auxvar_type) :: global_auxvar
  type(material_auxvar_type) :: material_auxvar
  type(option_type) :: option
  class(characteristic_curves_type) :: characteristic_curves
  PetscReal :: J(option%nflowdof,option%nflowdof)

  PetscReal :: vol_over_dt

  PetscInt :: ideriv
  type(richards_auxvar_type) :: rich_auxvar_pert
  type(global_auxvar_type) :: global_auxvar_pert
  ! leave as type
  type(material_auxvar_type) :: material_auxvar_pert
  PetscReal :: x(1), x_pert(1), pert, res(1), res_pert(1), J_pert(1,1)

  vol_over_dt = material_auxvar%volume/option%flow_dt

  ! accumulation term units = dkmol/dp
  J(1,1) = (material_auxvar%dporosity_dp*global_auxvar%sat(1)* &
            global_auxvar%den(1) + &
            (global_auxvar%sat(1)*rich_auxvar%dden_dp + &
             rich_auxvar%dsat_dp*global_auxvar%den(1)) * &
            material_auxvar%porosity) * &
            vol_over_dt

  if (option%flow%numerical_derivatives) then
    call GlobalAuxVarInit(global_auxvar_pert,option)
    call MaterialAuxVarInit(material_auxvar_pert,option)
    call RichardsAuxVarCopy(rich_auxvar,rich_auxvar_pert,option)
    call GlobalAuxVarCopy(global_auxvar,global_auxvar_pert,option)
    call MaterialAuxVarCopy(material_auxvar,material_auxvar_pert,option)
    x(1) = global_auxvar%pres(1)
    call RichardsAccumulation(rich_auxvar,global_auxvar,material_auxvar, &
                              option,res)
    ideriv = 1
    pert = max(dabs(x(ideriv)*perturbation_tolerance),0.1d0)
    x_pert = x
    if (x_pert(ideriv) < option%flow%reference_pressure) pert = -1.d0*pert
    x_pert(ideriv) = x_pert(ideriv) + pert

    call RichardsAuxVarCompute(x_pert(1),rich_auxvar_pert,global_auxvar_pert, &
                               material_auxvar_pert, &
                               characteristic_curves, &
                               -999, &
                               PETSC_TRUE,option)
    call RichardsAccumulation(rich_auxvar_pert,global_auxvar_pert, &
                              material_auxvar_pert, &
                              option,res_pert)
    J_pert(1,1) = (res_pert(1)-res(1))/pert
    J = J_pert
    call GlobalAuxVarStrip(global_auxvar_pert)
    call MaterialAuxVarStrip(material_auxvar_pert)
  endif

end subroutine RichardsAccumDerivative

! ************************************************************************** !

subroutine RichardsAccumulation(rich_auxvar,global_auxvar, &
                                material_auxvar, &
                                option,Res)
  !
  ! Computes the non-fixed portion of the accumulation
  ! term for the residual
  !
  ! Author: Glenn Hammond
  ! Date: 12/13/07
  !

  use Option_module
  use Material_Aux_module, only : material_auxvar_type

  implicit none

  type(richards_auxvar_type) :: rich_auxvar
  type(global_auxvar_type) :: global_auxvar
  type(material_auxvar_type) :: material_auxvar
  type(option_type) :: option
  PetscReal :: Res(1:option%nflowdof)

  PetscReal :: vol_over_dt

  vol_over_dt = material_auxvar%volume/option%flow_dt

  ! accumulation term units = kmol/s
  Res(1) = global_auxvar%sat(1) * global_auxvar%den(1) * &
           material_auxvar%porosity * vol_over_dt

end subroutine RichardsAccumulation

! ************************************************************************** !

subroutine RichardsFluxDerivative(rich_auxvar_up,global_auxvar_up, &
                                  material_auxvar_up, &
                                  rich_auxvar_dn,global_auxvar_dn, &
                                  material_auxvar_dn, &
                                  area, dist, &
                                  option, &
                                  characteristic_curves_up, &
                                  characteristic_curves_dn, &
                                  Jup,Jdn)
  !
  ! Computes the derivatives of the internal flux terms
  ! for the Jacobian
  !
  ! Author: Glenn Hammond
  ! Date: 12/13/07
  !
  use Option_module
  use Characteristic_Curves_module
  use Material_Aux_module
  use Connection_module

  implicit none

  type(richards_auxvar_type) :: rich_auxvar_up, rich_auxvar_dn
  type(global_auxvar_type) :: global_auxvar_up, global_auxvar_dn
  type(material_auxvar_type) :: material_auxvar_up, material_auxvar_dn
  type(option_type) :: option
  PetscReal :: v_darcy, area, dist(-1:3)
  class(characteristic_curves_type) :: characteristic_curves_up
  class(characteristic_curves_type) :: characteristic_curves_dn
  PetscReal :: Jup(option%nflowdof,option%nflowdof)
  PetscReal :: Jdn(option%nflowdof,option%nflowdof)

  PetscReal :: q
  PetscReal :: ukvr,Dq
  PetscReal :: dd_up, dd_dn, perm_up, perm_dn
  PetscReal :: dist_gravity
  PetscReal :: upweight,density_ave,gravity,dphi

  PetscReal :: dden_ave_dp_up, dden_ave_dp_dn
  PetscReal :: dgravity_dden_up, dgravity_dden_dn
  PetscReal :: dphi_dp_up, dphi_dp_dn
  PetscReal :: dukvr_dp_up, dukvr_dp_dn
!  PetscReal :: dukvr_x_dp_up, dukvr_x_dp_dn
!  PetscReal :: dukvr_y_dp_up, dukvr_y_dp_dn
!  PetscReal :: dukvr_z_dp_up, dukvr_z_dp_dn
  PetscReal :: dq_dp_up, dq_dp_dn

  PetscInt :: ideriv
  type(richards_auxvar_type) :: rich_auxvar_pert_up, rich_auxvar_pert_dn
  type(global_auxvar_type) :: global_auxvar_pert_up, global_auxvar_pert_dn
  ! leave as type
  type(material_auxvar_type) :: material_auxvar_pert_up, material_auxvar_pert_dn
  PetscReal :: x_up(1), x_dn(1), x_pert_up(1), x_pert_dn(1), pert_up, pert_dn, &
            res(1), res_pert_up(1), res_pert_dn(1), J_pert_up(1,1), J_pert_dn(1,1)

  v_darcy = 0.D0
  ukvr = 0.d0

  Jup = 0.d0
  Jdn = 0.d0

  dden_ave_dp_up = 0.d0
  dden_ave_dp_dn = 0.d0
  dgravity_dden_up = 0.d0
  dgravity_dden_dn = 0.d0
  dphi_dp_up = 0.d0
  dphi_dp_dn = 0.d0
  dukvr_dp_up = 0.d0
  dukvr_dp_dn = 0.d0
  dq_dp_up = 0.d0
  dq_dp_dn = 0.d0

  call ConnectionCalculateDistances(dist,option%gravity,dd_up,dd_dn, &
                                    dist_gravity,upweight)
  call PermeabilityTensorToScalar(material_auxvar_up,dist,perm_up)
  call PermeabilityTensorToScalar(material_auxvar_dn,dist,perm_dn)

  Dq = (perm_up * perm_dn)/(dd_up*perm_dn + dd_dn*perm_up)

! Flow term
  if (rich_auxvar_up%kvr > eps .or. &
      rich_auxvar_dn%kvr > eps) then

    if (global_auxvar_up%sat(1) <eps) then
      upweight=0.d0
    else if (global_auxvar_dn%sat(1) <eps) then
      upweight=1.d0
    endif
    density_ave = upweight*global_auxvar_up%den(1)+ &
                  (1.D0-upweight)*global_auxvar_dn%den(1)
    dden_ave_dp_up = upweight*rich_auxvar_up%dden_dp
    dden_ave_dp_dn = (1.D0-upweight)*rich_auxvar_dn%dden_dp

    gravity = (upweight*global_auxvar_up%den(1) + &
              (1.D0-upweight)*global_auxvar_dn%den(1)) &
              * FMWH2O * dist_gravity
    dgravity_dden_up = upweight*FMWH2O*dist_gravity
    dgravity_dden_dn = (1.d0-upweight)*FMWH2O*dist_gravity

    dphi = global_auxvar_up%pres(1) - global_auxvar_dn%pres(1)  + gravity
    dphi_dp_up = 1.d0 + dgravity_dden_up*rich_auxvar_up%dden_dp
    dphi_dp_dn = -1.d0 + dgravity_dden_dn*rich_auxvar_dn%dden_dp

    if (dphi>=0.D0) then
      ukvr = rich_auxvar_up%kvr
      dukvr_dp_up = rich_auxvar_up%dkvr_dp
    else
      ukvr = rich_auxvar_dn%kvr
      dukvr_dp_dn = rich_auxvar_dn%dkvr_dp
    endif

    if (ukvr>floweps) then
      v_darcy= Dq * ukvr * dphi

      q = v_darcy * area
      dq_dp_up = Dq*(dukvr_dp_up*dphi+ukvr*dphi_dp_up)*area
      dq_dp_dn = Dq*(dukvr_dp_dn*dphi+ukvr*dphi_dp_dn)*area

      Jup(1,1) = (dq_dp_up*density_ave+q*dden_ave_dp_up)
      Jdn(1,1) = (dq_dp_dn*density_ave+q*dden_ave_dp_dn)
    endif
  endif

 ! note: Res is the flux contribution, for node up J = J + Jup
 !                                              dn J = J - Jdn

  if (option%flow%numerical_derivatives) then
    call GlobalAuxVarInit(global_auxvar_pert_up,option)
    call GlobalAuxVarInit(global_auxvar_pert_dn,option)
    call MaterialAuxVarInit(material_auxvar_pert_up,option)
    call MaterialAuxVarInit(material_auxvar_pert_dn,option)
    call RichardsAuxVarCopy(rich_auxvar_up,rich_auxvar_pert_up,option)
    call RichardsAuxVarCopy(rich_auxvar_dn,rich_auxvar_pert_dn,option)
    call GlobalAuxVarCopy(global_auxvar_up,global_auxvar_pert_up,option)
    call GlobalAuxVarCopy(global_auxvar_dn,global_auxvar_pert_dn,option)
    call MaterialAuxVarCopy(material_auxvar_up,material_auxvar_pert_up,option)
    call MaterialAuxVarCopy(material_auxvar_dn,material_auxvar_pert_dn,option)
    x_up(1) = global_auxvar_up%pres(1)
    x_dn(1) = global_auxvar_dn%pres(1)
    call RichardsFlux(rich_auxvar_up,global_auxvar_up,material_auxvar_up, &
                      rich_auxvar_dn,global_auxvar_dn,material_auxvar_dn, &
                      area, dist, &
                      option,v_darcy,res)
    ideriv = 1
!    pert_up = x_up(ideriv)*perturbation_tolerance
    pert_up = max(dabs(x_up(ideriv)*perturbation_tolerance),0.1d0)
    if (x_up(ideriv) < option%flow%reference_pressure) pert_up = -1.d0*pert_up
!    pert_dn = x_dn(ideriv)*perturbation_tolerance
    pert_dn = max(dabs(x_dn(ideriv)*perturbation_tolerance),0.1d0)
    if (x_dn(ideriv) < option%flow%reference_pressure) pert_dn = -1.d0*pert_dn
    x_pert_up = x_up
    x_pert_dn = x_dn
    x_pert_up(ideriv) = x_pert_up(ideriv) + pert_up
    x_pert_dn(ideriv) = x_pert_dn(ideriv) + pert_dn
    call RichardsAuxVarCompute(x_pert_up(1),rich_auxvar_pert_up, &
                               global_auxvar_pert_up, &
                               material_auxvar_pert_up, &
                               characteristic_curves_up, &
                               -999, &
                               PETSC_TRUE,option)
    call RichardsAuxVarCompute(x_pert_dn(1),rich_auxvar_pert_dn, &
                               global_auxvar_pert_dn, &
                               material_auxvar_pert_dn, &
                               characteristic_curves_dn, &
                               -999, &
                               PETSC_TRUE,option)
    call RichardsFlux(rich_auxvar_pert_up,global_auxvar_pert_up, &
                      material_auxvar_pert_up, &
                      rich_auxvar_dn,global_auxvar_dn, &
                      material_auxvar_dn, &
                      area, dist, &
                      option,v_darcy,res_pert_up)
    call RichardsFlux(rich_auxvar_up,global_auxvar_up, &
                      material_auxvar_up, &
                      rich_auxvar_pert_dn,global_auxvar_pert_dn, &
                      material_auxvar_pert_dn, &
                      area, dist, &
                      option,v_darcy,res_pert_dn)
    J_pert_up(1,ideriv) = (res_pert_up(1)-res(1))/pert_up
    J_pert_dn(1,ideriv) = (res_pert_dn(1)-res(1))/pert_dn
    Jup = J_pert_up
    Jdn = J_pert_dn
    call GlobalAuxVarStrip(global_auxvar_pert_up)
    call GlobalAuxVarStrip(global_auxvar_pert_dn)
    call MaterialAuxVarStrip(material_auxvar_pert_up)
    call MaterialAuxVarStrip(material_auxvar_pert_dn)
  endif

end subroutine RichardsFluxDerivative

! ************************************************************************** !

subroutine RichardsFlux(rich_auxvar_up,global_auxvar_up, &
                        material_auxvar_up, &
                        rich_auxvar_dn,global_auxvar_dn, &
                        material_auxvar_dn, &
                        area, dist, &
                        option,v_darcy,Res)
  !
  ! Computes the internal flux terms for the residual
  !
  ! Author: Glenn Hammond
  ! Date: 12/13/07
  !
  use Option_module
  use Material_Aux_module
  use Connection_module

  implicit none

  type(richards_auxvar_type) :: rich_auxvar_up, rich_auxvar_dn
  type(global_auxvar_type) :: global_auxvar_up, global_auxvar_dn
  type(material_auxvar_type) :: material_auxvar_up, material_auxvar_dn
  type(option_type) :: option
  PetscReal :: v_darcy, area, dist(-1:3)
  PetscReal :: Res(1:option%nflowdof)

  PetscReal :: dist_gravity  ! distance along gravity vector
  PetscReal :: dd_up, dd_dn, perm_up, perm_dn
  PetscReal :: fluxm, q
  PetscReal :: ukvr,Dq
  PetscReal :: upweight, density_ave, gravity, dphi

  fluxm = 0.d0
  v_darcy = 0.D0
  ukvr = 0.d0

  call ConnectionCalculateDistances(dist,option%gravity,dd_up,dd_dn, &
                                    dist_gravity,upweight)
  call PermeabilityTensorToScalar(material_auxvar_up,dist,perm_up)
  call PermeabilityTensorToScalar(material_auxvar_dn,dist,perm_dn)

  Dq = (perm_up * perm_dn)/(dd_up*perm_dn + dd_dn*perm_up)

! Flow term
  if (rich_auxvar_up%kvr > eps .or. &
      rich_auxvar_dn%kvr > eps) then
    if (global_auxvar_up%sat(1) <eps) then
      upweight=0.d0
    else if (global_auxvar_dn%sat(1) <eps) then
      upweight=1.d0
    endif


    density_ave = upweight*global_auxvar_up%den(1)+ &
                  (1.D0-upweight)*global_auxvar_dn%den(1)

    gravity = (upweight*global_auxvar_up%den(1) + &
              (1.D0-upweight)*global_auxvar_dn%den(1)) &
              * FMWH2O * dist_gravity

    dphi = global_auxvar_up%pres(1) - global_auxvar_dn%pres(1)  + gravity

    if (dphi>=0.D0) then
      ukvr = rich_auxvar_up%kvr
    else
      ukvr = rich_auxvar_dn%kvr
    endif

    if (ukvr>floweps) then
      v_darcy= Dq * ukvr * dphi

      q = v_darcy * area

      fluxm = q*density_ave
    endif
  endif

  Res(1) = fluxm
 ! note: Res is the flux contribution, for node 1 R = R + Res_FL
 !                                              2 R = R - Res_FL

end subroutine RichardsFlux

! ************************************************************************** !

subroutine RichardsBCFluxDerivative(ibndtype,auxvars, &
                                    rich_auxvar_up,global_auxvar_up, &
                                    rich_auxvar_dn,global_auxvar_dn, &
                                    material_auxvar_dn, &
                                    area,dist,option, &
                                    characteristic_curves_dn, &
                                    Jdn)
  !
  ! Computes the derivatives of the boundary flux
  ! terms for the Jacobian
  !
  ! Author: Glenn Hammond
  ! Date: 12/13/07
  !
  use Option_module
  use Characteristic_Curves_module
  use Material_Aux_module
  use EOS_Water_module
  use Utility_module

  implicit none

  PetscInt :: ibndtype(:)
  type(richards_auxvar_type) :: rich_auxvar_up, rich_auxvar_dn
  type(global_auxvar_type) :: global_auxvar_up, global_auxvar_dn
  type(material_auxvar_type) :: material_auxvar_dn
  type(option_type) :: option
  PetscReal :: auxvars(:) ! from aux_real_var array in boundary condition
  PetscReal :: area
  ! dist(-1) = fraction_upwind
  ! dist(0) = magnitude
  ! dist(1:3) = unit vector
  ! dist(0)*dist(1:3) = vector
  PetscReal :: dist(-1:3)
  class(characteristic_curves_type) :: characteristic_curves_dn
  PetscReal :: Jdn(option%nflowdof,option%nflowdof)

  PetscReal :: dist_gravity  ! distance along gravity vector
  PetscReal :: perm_dn

  PetscReal :: v_darcy
  PetscReal :: q,density_ave
  PetscReal :: ukvr,Dq
  PetscReal :: upweight,gravity,dphi

  PetscReal :: dden_ave_dp_dn
  PetscReal :: dgravity_dden_dn
  PetscReal :: dphi_dp_dn
  PetscReal :: dukvr_dp_dn
  PetscReal :: dq_dp_dn
  PetscInt :: pressure_bc_type

  PetscInt ::  ideriv
  type(richards_auxvar_type) :: rich_auxvar_pert_dn, rich_auxvar_pert_up
  type(global_auxvar_type) :: global_auxvar_pert_dn, global_auxvar_pert_up
  type(material_auxvar_type), allocatable :: material_auxvar_pert_dn, &
                                              material_auxvar_pert_up
  PetscReal :: x_dn(1), x_up(1), x_pert_dn(1), x_pert_up(1), pert_dn, res(1), &
            res_pert_dn(1), J_pert_dn(1,1)

  v_darcy = 0.d0
  ukvr = 0.d0
  density_ave = 0.d0
  q = 0.d0

  Jdn = 0.d0

  dden_ave_dp_dn = 0.d0
  dgravity_dden_dn = 0.d0
  dphi_dp_dn = 0.d0
  dukvr_dp_dn = 0.d0
  dq_dp_dn = 0.d0

  call PermeabilityTensorToScalar(material_auxvar_dn,dist,perm_dn)

  ! Flow
  pressure_bc_type = ibndtype(RICHARDS_PRESSURE_DOF)
  select case(pressure_bc_type)
    ! figure out the direction of flow
    case(DIRICHLET_BC,DIRICHLET_SEEPAGE_BC,DIRICHLET_CONDUCTANCE_BC, &
         HYDROSTATIC_BC,HYDROSTATIC_SEEPAGE_BC,HYDROSTATIC_CONDUCTANCE_BC, &
         HET_SURF_HYDROSTATIC_SEEPAGE_BC, &
         HET_DIRICHLET_BC,HET_HYDROSTATIC_SEEPAGE_BC, &
         HET_HYDROSTATIC_CONDUCTANCE_BC)

      ! dist(0) = scalar - magnitude of distance
      ! gravity = vector(3)
      ! dist(1:3) = vector(3) - unit vector
      dist_gravity = dist(0) * dot_product(option%gravity,dist(1:3))

      if (pressure_bc_type == HYDROSTATIC_CONDUCTANCE_BC .or. &
          pressure_bc_type == DIRICHLET_CONDUCTANCE_BC .or. &
          pressure_bc_type == HET_HYDROSTATIC_CONDUCTANCE_BC) then
        Dq = auxvars(RICHARDS_CONDUCTANCE_DOF)
      else
        Dq = perm_dn / dist(0)
      endif
      ! Flow term
      if (rich_auxvar_up%kvr > eps .or. &
          rich_auxvar_dn%kvr > eps) then
        upweight=1.D0
        if (global_auxvar_up%sat(1) < eps) then
          upweight=0.d0
        else if (global_auxvar_dn%sat(1) < eps) then
          upweight=1.d0
        endif

        density_ave = upweight*global_auxvar_up%den(1) + &
                      (1.D0-upweight)*global_auxvar_dn%den(1)
        dden_ave_dp_dn = (1.D0-upweight)*rich_auxvar_dn%dden_dp

        gravity = (upweight*global_auxvar_up%den(1) + &
                  (1.D0-upweight)*global_auxvar_dn%den(1)) &
                  * FMWH2O * dist_gravity
        dgravity_dden_dn = (1.d0-upweight)*FMWH2O*dist_gravity

        dphi = global_auxvar_up%pres(1) - global_auxvar_dn%pres(1) + gravity
        dphi_dp_dn = -1.d0 + dgravity_dden_dn*rich_auxvar_dn%dden_dp

        select case(pressure_bc_type)
          case(HYDROSTATIC_SEEPAGE_BC,HYDROSTATIC_CONDUCTANCE_BC, &
               DIRICHLET_SEEPAGE_BC,DIRICHLET_CONDUCTANCE_BC, &
               HET_SURF_HYDROSTATIC_SEEPAGE_BC, &
               HET_HYDROSTATIC_SEEPAGE_BC,HET_HYDROSTATIC_CONDUCTANCE_BC)
                ! flow in
            if (dphi > 0.d0 .and. &
                ! boundary cell is <= pref
                global_auxvar_up%pres(1)- &
                  option%flow%reference_pressure < eps) then
              dphi = 0.d0
              dphi_dp_dn = 0.d0
            endif
        end select

        if (dphi>=0.D0) then
          ukvr = rich_auxvar_up%kvr
        else
          ukvr = rich_auxvar_dn%kvr
          dukvr_dp_dn = rich_auxvar_dn%dkvr_dp
        endif

        if (ukvr*Dq>floweps) then
          v_darcy = Dq * ukvr * dphi
          q = v_darcy * area
          dq_dp_dn = Dq*(dukvr_dp_dn*dphi + ukvr*dphi_dp_dn)*area
        endif

      endif

    case(NEUMANN_BC)
      if (dabs(auxvars(RICHARDS_PRESSURE_DOF)) > floweps) then
        v_darcy = auxvars(RICHARDS_PRESSURE_DOF)
        if (v_darcy > 0.d0) then
          density_ave = global_auxvar_up%den(1)
        else
          density_ave = global_auxvar_dn%den(1)
          dden_ave_dp_dn = rich_auxvar_dn%dden_dp
        endif
        q = v_darcy * area
      endif

    case(UNIT_GRADIENT_BC)

      if(rich_auxvar_dn%kvr > eps) then
        dphi = dot_product(option%gravity,dist(1:3))* &
                           global_auxvar_dn%den(1)*FMWH2O
        density_ave = global_auxvar_dn%den(1)

        dphi_dp_dn = dot_product(option%gravity,dist(1:3))* &
                                 rich_auxvar_dn%dden_dp*FMWH2O
        dden_ave_dp_dn = rich_auxvar_dn%dden_dp

        ! since boundary auxvar is meaningless (no pressure specified there), only use cell
        ukvr = rich_auxvar_dn%kvr
        dukvr_dp_dn = rich_auxvar_dn%dkvr_dp

        if (ukvr*perm_dn>floweps) then
          v_darcy = perm_dn * ukvr * dphi
          q = v_darcy*area
          dq_dp_dn = perm_dn*(dukvr_dp_dn*dphi+ukvr*dphi_dp_dn)*area
        endif

      endif

  end select

  Jdn(1,1) = (dq_dp_dn*density_ave+q*dden_ave_dp_dn)

  if (option%flow%numerical_derivatives) then
    call GlobalAuxVarInit(global_auxvar_pert_up,option)
    call GlobalAuxVarInit(global_auxvar_pert_dn,option)
    allocate(material_auxvar_pert_up,material_auxvar_pert_dn)
    call MaterialAuxVarInit(material_auxvar_pert_up,option)
    call MaterialAuxVarInit(material_auxvar_pert_dn,option)
    call RichardsAuxVarCopy(rich_auxvar_up,rich_auxvar_pert_up,option)
    call RichardsAuxVarCopy(rich_auxvar_dn,rich_auxvar_pert_dn,option)
    call GlobalAuxVarCopy(global_auxvar_up,global_auxvar_pert_up,option)
    call GlobalAuxVarCopy(global_auxvar_dn,global_auxvar_pert_dn,option)
    call MaterialAuxVarCopy(material_auxvar_dn,material_auxvar_pert_up, &
                            option)
    call MaterialAuxVarCopy(material_auxvar_dn,material_auxvar_pert_dn, &
                            option)
    x_up(1) = global_auxvar_up%pres(1)
    x_dn(1) = global_auxvar_dn%pres(1)
    ideriv = 1
    if (ibndtype(ideriv) == ZERO_GRADIENT_BC) then
      x_up(ideriv) = x_dn(ideriv)
    endif
    call RichardsBCFlux(ibndtype,auxvars, &
                        rich_auxvar_up,global_auxvar_up, &
                        rich_auxvar_dn,global_auxvar_dn, &
                        material_auxvar_dn, &
                        area,dist,option,v_darcy,res)
    if (pressure_bc_type == ZERO_GRADIENT_BC) then
      x_pert_up = x_up
    endif
    ideriv = 1
!    pert_dn = x_dn(ideriv)*perturbation_tolerance
    pert_dn = max(dabs(x_dn(ideriv)*perturbation_tolerance),0.1d0)
    if (x_dn(ideriv) < option%flow%reference_pressure) pert_dn = -1.d0*pert_dn
    x_pert_dn = x_dn
    x_pert_dn(ideriv) = x_pert_dn(ideriv) + pert_dn
    x_pert_up = x_up
    if (ibndtype(ideriv) == ZERO_GRADIENT_BC) then
      x_pert_up(ideriv) = x_pert_dn(ideriv)
    endif
    call RichardsAuxVarCompute(x_pert_dn(1),rich_auxvar_pert_dn, &
                               global_auxvar_pert_dn, &
                               material_auxvar_pert_dn, &
                               characteristic_curves_dn, &
                               -999, &
                               PETSC_TRUE,option)
    call RichardsAuxVarCompute(x_pert_up(1),rich_auxvar_pert_up, &
                               global_auxvar_pert_up, &
                               material_auxvar_pert_up, &
                               characteristic_curves_dn, &
                               -999, &
                               PETSC_TRUE,option)
    call RichardsBCFlux(ibndtype,auxvars, &
                        rich_auxvar_pert_up,global_auxvar_pert_up, &
                        rich_auxvar_pert_dn,global_auxvar_pert_dn, &
                        material_auxvar_pert_dn, &
                        area,dist,option,v_darcy,res_pert_dn)
    J_pert_dn(1,ideriv) = (res_pert_dn(1)-res(1))/pert_dn
    Jdn = J_pert_dn
    call GlobalAuxVarStrip(global_auxvar_pert_up)
    call GlobalAuxVarStrip(global_auxvar_pert_dn)
    call MaterialAuxVarStrip(material_auxvar_pert_up)
    call MaterialAuxVarStrip(material_auxvar_pert_dn)
    deallocate(material_auxvar_pert_up,material_auxvar_pert_dn)
  endif

end subroutine RichardsBCFluxDerivative

! ************************************************************************** !

subroutine RichardsBCFlux(ibndtype,auxvars, &
                          rich_auxvar_up, global_auxvar_up, &
                          rich_auxvar_dn, global_auxvar_dn, &
                          material_auxvar_dn, &
                          area, dist, option,v_darcy,Res)
  !
  ! Computes the  boundary flux terms for the residual
  !
  ! Author: Glenn Hammond
  ! Date: 12/13/07
  !
  use Option_module
  use Material_Aux_module
  use EOS_Water_module
  use Utility_module

  implicit none

  PetscInt :: ibndtype(:)
  type(richards_auxvar_type) :: rich_auxvar_up, rich_auxvar_dn
  type(global_auxvar_type) :: global_auxvar_up, global_auxvar_dn
  type(material_auxvar_type) :: material_auxvar_dn
  type(option_type) :: option
  PetscReal :: auxvars(:) ! from aux_real_var array
  PetscReal :: v_darcy, area
  ! dist(-1) = fraction_upwind - not applicable here
  ! dist(0) = magnitude
  ! dist(1:3) = unit vector
  ! dist(0)*dist(1:3) = vector
  PetscReal :: dist(-1:3)
  PetscReal :: Res(1:option%nflowdof)

  PetscReal :: dist_gravity  ! distance along gravity vector

  PetscReal :: perm_dn
  PetscReal :: fluxm,q,density_ave
  PetscReal :: ukvr,Dq
  PetscReal :: upweight,gravity,dphi
  PetscInt :: pressure_bc_type

  fluxm = 0.d0
  v_darcy = 0.d0
  density_ave = 0.d0
  q = 0.d0
  ukvr = 0.d0

  call PermeabilityTensorToScalar(material_auxvar_dn,dist,perm_dn)

  ! Flow
  pressure_bc_type = ibndtype(RICHARDS_PRESSURE_DOF)
  select case(pressure_bc_type)
    ! figure out the direction of flow
    case(DIRICHLET_BC,DIRICHLET_SEEPAGE_BC,DIRICHLET_CONDUCTANCE_BC, &
         HYDROSTATIC_BC,HYDROSTATIC_SEEPAGE_BC,HYDROSTATIC_CONDUCTANCE_BC, &
         HET_SURF_HYDROSTATIC_SEEPAGE_BC, &
         HET_DIRICHLET_BC,HET_HYDROSTATIC_SEEPAGE_BC, &
         HET_HYDROSTATIC_CONDUCTANCE_BC)

      ! dist(0) = scalar - magnitude of distance
      ! gravity = vector(3)
      ! dist(1:3) = vector(3) - unit vector
      dist_gravity = dist(0) * dot_product(option%gravity,dist(1:3))

      if (pressure_bc_type == HYDROSTATIC_CONDUCTANCE_BC .or. &
          pressure_bc_type == DIRICHLET_CONDUCTANCE_BC .or. &
          pressure_bc_type == HET_HYDROSTATIC_CONDUCTANCE_BC) then
        Dq = auxvars(RICHARDS_CONDUCTANCE_DOF)
      else
        Dq = perm_dn / dist(0)
      endif
      ! Flow term
      if (rich_auxvar_up%kvr > eps .or. &
          rich_auxvar_dn%kvr > eps) then
        upweight=1.D0
        if (global_auxvar_up%sat(1) < eps) then
          upweight=0.d0
        else if (global_auxvar_dn%sat(1) < eps) then
          upweight=1.d0
        endif
        density_ave = upweight*global_auxvar_up%den(1)+(1.D0-upweight)*global_auxvar_dn%den(1)

        gravity = (upweight*global_auxvar_up%den(1) + &
                  (1.D0-upweight)*global_auxvar_dn%den(1)) &
                  * FMWH2O * dist_gravity

        dphi = global_auxvar_up%pres(1) - global_auxvar_dn%pres(1) + gravity

        select case(pressure_bc_type)
          case(HYDROSTATIC_SEEPAGE_BC,HYDROSTATIC_CONDUCTANCE_BC, &
               DIRICHLET_SEEPAGE_BC,DIRICHLET_CONDUCTANCE_BC, &
               HET_SURF_HYDROSTATIC_SEEPAGE_BC, &
               HET_HYDROSTATIC_SEEPAGE_BC,HET_HYDROSTATIC_CONDUCTANCE_BC)
                ! flow in
            if (dphi > 0.d0 .and. &
                ! boundary cell is <= pref
                global_auxvar_up%pres(1)- &
                  option%flow%reference_pressure < eps) then
              dphi = 0.d0
            endif
        end select

        if (dphi>=0.D0) then
          ukvr = rich_auxvar_up%kvr
        else
          ukvr = rich_auxvar_dn%kvr
        endif
        if (ukvr*Dq>floweps) then
          v_darcy = Dq * ukvr * dphi
        endif
      endif

    case(NEUMANN_BC)
      if (dabs(auxvars(RICHARDS_PRESSURE_DOF)) > floweps) then
        v_darcy = auxvars(RICHARDS_PRESSURE_DOF)

        if (v_darcy > 0.d0) then
          density_ave = global_auxvar_up%den(1)
        else
          density_ave = global_auxvar_dn%den(1)
        endif
      endif

    case(UNIT_GRADIENT_BC)

      dphi = dot_product(option%gravity,dist(1:3))*global_auxvar_dn%den(1)*FMWH2O
      density_ave = global_auxvar_dn%den(1)

      ! since boundary auxvar is meaningless (no pressure specified there), only use cell
      ukvr = rich_auxvar_dn%kvr

      if (ukvr*perm_dn>floweps) then
        v_darcy = perm_dn * ukvr * dphi
      endif

  end select

  q = v_darcy * area

  fluxm = q*density_ave

  Res(1)=fluxm

end subroutine RichardsBCFlux

end module Richards_Common_module
