! ----------------------------------------------------------------------------------- !
! ----------------------------------------------------------------------------------- !
! This module solves for the radiative transfer equation by ray-tracing for
! multi-level atoms, using the MALI scheme.
!
! Outputs:
! - Flux (\lambda) [J.s^{-1}.m^{-2}.Hz^{-1}]
! - Irradiation map around a line [J.s^{-1}.m^{-2}.Hz^{-1}.pix^{-1}] !sr^{-1}
!   --> not exactly, it is multiplied by the pixel solid angle seen from the Earth.
! TBD - levels population n
! TBD - Cooling rates PHIij = njRij - niRji
! TBD - Contribution function around a line
! - Electron density
! TBD - Fixed radiative rates
! TBD - Full NLTE line transfer
! TBD - PFR on the "atoms'frame - observer's frame" approach
!
! It uses all the NLTE modules in NLTE/ and it is called in mcfost.f90 similar to
! mol_transfer.f90
!
! Note: SI units, velocity in m/s, density in kg/m3, radius in m
! ----------------------------------------------------------------------------------- !
! ----------------------------------------------------------------------------------- !

MODULE AtomicTransfer

 use metal, only                        : Background, BackgroundContinua, BackgroundLines
 use spectrum_type
 use atmos_type
 use readatom
 use lte
 use constant, only 					: MICRON_TO_NM
 use collision
 use solvene
 use statequil_atoms
 use writeatom
 use simple_models, only 				: magneto_accretion_model
 !$ use omp_lib

 !MCFOST's original modules
 use input
 use parametres
 use grid
 use optical_depth, only				: atom_optical_length_tot, optical_length_tot
 use dust_prop
 use dust_transfer, only 				: compute_stars_map
 use dust_ray_tracing, only 			: init_directions_ray_tracing ,            &
                              			  tab_u_RT, tab_v_RT, tab_w_RT, tab_RT_az, &
                              			  tab_RT_incl, stars_map, kappa, stars_map_cont
 use stars
 use wavelengths
 use density

 IMPLICIT NONE

 CONTAINS


 SUBROUTINE INTEG_RAY_LINE(id,icell_in,x,y,z,u,v,w,iray,labs)
 ! ------------------------------------------------------------------------------- !
  ! This routine performs integration of the transfer equation along a ray
  ! crossing different cells.
  ! --> Atomic Lines case.
  !
  ! voir integ_ray_mol from mcfost
  ! All necessary quantities are initialised before this routine, and everything
  ! call, update, rewrite atoms% and spectrum%
  ! if atmos%nHtot or atmos%T is 0, the cell is empty
  !
  ! id = processor information, iray = index of the running ray
  ! what is labs? lsubtract_avg?
 ! ------------------------------------------------------------------------------- !

  integer, intent(in) :: id, icell_in, iray
  double precision, intent(in) :: u,v,w
  double precision, intent(in) :: x,y,z
  logical, intent(in) :: labs !used in NLTE but why?
  double precision :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before
  double precision, dimension(NLTEspec%Nwaves) :: Snu, Snu_c
  double precision, dimension(NLTEspec%Nwaves) :: tau, tau_c, dtau_c, dtau
  integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star
  double precision :: facteur_tau !used only in molecular line to have emission for one
                                  !  half of the disk only. Note used in AL-RT.
                                  !  this is passed through the lonly_top or lonly_bottom.
  logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars

  x1=x;y1=y;z1=z
  x0=x;y0=y;z0=z
  next_cell = icell_in
  nbr_cell = 0

  tau = 0.0_dp !go from surface down to the star
  tau_c = 0.0_dp

  ! Reset, because when we compute the flux map
  ! with emission_line_map, we only use one ray, iray=1
  ! and the same space is used for emergent I.
  ! Therefore it is needed to reset it.
  NLTEspec%I(:,iray,id) = 0d0
  NLTEspec%Ic(:,iray,id) = 0d0

  ! -------------------------------------------------------------- !
  !*** propagation dans la grille ***!
  ! -------------------------------------------------------------- !
  ! Will the ray intersect a star
  call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)

  ! Boucle infinie sur les cellules
  infinie : do ! Boucle infinie
    ! Indice de la cellule
    icell = next_cell
    x0=x1 ; y0=y1 ; z0=z1

    if (icell <= n_cells) then
     !lcellule_non_vide=.true.
     lcellule_non_vide = atmos%lcompute_atomRT(icell)
    else
     lcellule_non_vide=.false.
    endif

    ! Test sortie ! "The ray has reach the end of the grid"
    if (test_exit_grid(icell, x0, y0, z0)) RETURN
    if (lintersect_stars) then
      if (icell == icell_star) RETURN
    endif

    nbr_cell = nbr_cell + 1

    ! Calcul longeur de vol et profondeur optique dans la cellule
    previous_cell = 0 ! unused, just for Voronoi

    call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell, &
                     l, l_contrib, l_void_before)


!     if (.not.atmos%lcompute_atomRT(icell)) lcellule_non_vide = .false. !chi and chi_c = 0d0, cell is transparent  
!	   this makes the code to break down  --> the atomRT is defined on n_cells
!		but the infinite loop runs over "virtual" cells, which can be be 
!		out of atomRT boundary

    !count opacity only if the cell is filled, else go to next cell
    if (lcellule_non_vide) then
     lsubtract_avg = ((nbr_cell == 1).and.labs) !not used yet
     ! opacities in m^-1
     l_contrib = l_contrib * AU_to_m !l_contrib in AU
     if ((nbr_cell == 1).and.labs)  ds(iray,id) = l * AU_to_m


     CALL initAtomOpac(id) !set opac to 0 for this cell and thread id
     !! Compute background opacities for PASSIVE bound-bound and bound-free transitions
     !! at all wavelength points including vector fields in the bound-bound transitions
     if (lstore_opac) then
      CALL BackgroundLines(id, icell, x0, y0, z0, x1, y1, z1, u, v, w, l)
      dtau(:)   = l_contrib * (NLTEspec%AtomOpac%chi_p(:,id)+NLTEspec%AtomOpac%chi(:,id)+&
                    NLTEspec%AtomOpac%Kc(icell,:,1))
      dtau_c(:) = l_contrib * NLTEspec%AtomOpac%Kc(icell,:,1)

      Snu = (NLTEspec%AtomOpac%jc(icell,:) + &
               NLTEspec%AtomOpac%eta_p(:,id) + NLTEspec%AtomOpac%eta(:,id) + &
                  NLTEspec%AtomOpac%Kc(icell,:,2) * NLTEspec%J(:,id)) / &
                 (NLTEspec%AtomOpac%Kc(icell,:,1) + &
                 NLTEspec%AtomOpac%chi_p(:,id) + NLTEspec%AtomOpac%chi(:,id) + 1d-300)

      Snu_c = (NLTEspec%AtomOpac%jc(icell,:) + &
            NLTEspec%AtomOpac%Kc(icell,:,2) * NLTEspec%Jc(:,id)) / &
            (NLTEspec%AtomOpac%Kc(icell,:,1) + 1d-300)
     else
      CALL Background(id, icell, x0, y0, z0, x1, y1, z1, u, v, w, l) !x,y,z,u,v,w,x1,y1,z1
                                !define the projection of the vector field (velocity, B...)
                                !at each spatial location.

      ! Epaisseur optique
      ! chi_p contains both thermal and continuum scattering extinction
      dtau(:)   =  l_contrib * (NLTEspec%AtomOpac%chi_p(:,id)+NLTEspec%AtomOpac%chi(:,id))
      dtau_c(:) = l_contrib * NLTEspec%AtomOpac%chi_c(:,id)

      ! Source function
      ! No dust yet
      ! J and Jc are the mean radiation field for total and continuum intensities
      ! it multiplies the continuum scattering coefficient for isotropic (unpolarised)
      ! scattering. chi, eta are opacity and emissivity for ACTIVE lines.
      Snu = (NLTEspec%AtomOpac%eta_p(:,id) + NLTEspec%AtomOpac%eta(:,id) + &
                  NLTEspec%AtomOpac%sca_c(:,id) * NLTEspec%J(:,id)) / &
                 (NLTEspec%AtomOpac%chi_p(:,id) + NLTEspec%AtomOpac%chi(:,id) + 1d-300)


      ! continuum source function
      Snu_c = (NLTEspec%AtomOpac%eta_c(:,id) + &
            NLTEspec%AtomOpac%sca_c(:,id) * NLTEspec%Jc(:,id)) / &
            (NLTEspec%AtomOpac%chi_c(:,id) + 1d-300)
    end if
    !In ray-traced map (which is used this subroutine) we integrate from the observer
    ! to the source(s), but we actually get the outgoing intensity/flux. Direct
    !intgreation of the RTE from the observer to the source result in having the
    ! inward flux and intensity. Integration from the source to the observer is done
    ! when computing the mean intensity: Sum_ray I*exp(-dtau)+S*(1-exp(-dtau))
    NLTEspec%I(:,iray,id) = NLTEspec%I(:,iray,id) + &
                             exp(-tau) * (1.0_dp - exp(-dtau)) * Snu
    NLTEspec%Ic(:,iray,id) = NLTEspec%Ic(:,iray,id) + &
                             exp(-tau_c) * (1.0_dp - exp(-dtau_c)) * Snu_c
!     NLTEspec%I(:,iray,id) = NLTEspec%I(:,iray,id) + dtau*Snu*dexp(-tau)
!     NLTEspec%Ic(:,iray,id) = NLTEspec%Ic(:,iray,id) + dtau_c*Snu_c*dexp(-tau_c)
    NLTEspec%StokesV(:,iray,id) = NLTEspec%StokesV(:,iray,id) + &
                             exp(-tau) * (1.0_dp - exp(-dtau)) * NLTEspec%S_QUV(3,:)

!      !!surface superieure ou inf, not used with AL-RT
     facteur_tau = 1.0
!      if (lonly_top    .and. z0 < 0.) facteur_tau = 0.0
!      if (lonly_bottom .and. z0 > 0.) facteur_tau = 0.0

     ! Mise a jour profondeur optique pour cellule suivante
     ! dtau = chi * ds
     tau = tau + dtau * facteur_tau
     tau_c = tau_c + dtau_c

     ! Define PSI Operators here
    end if  ! lcellule_non_vide
  end do infinie
  ! -------------------------------------------------------------- !
  ! -------------------------------------------------------------- !


  RETURN
  END SUBROUTINE INTEG_RAY_LINE

  SUBROUTINE FLUX_PIXEL_LINE(&
         id,ibin,iaz,n_iter_min,n_iter_max,ipix,jpix,pixelcorner,pixelsize,dx,dy,u,v,w)
  ! -------------------------------------------------------------- !
   ! Computes the flux emerging out of a pixel.
   ! see: mol_transfer.f90/intensite_pixel_mol()
  ! -------------------------------------------------------------- !

   integer, intent(in) :: ipix,jpix,id, n_iter_min, n_iter_max, ibin, iaz
   double precision, dimension(3), intent(in) :: pixelcorner,dx,dy
   double precision, intent(in) :: pixelsize,u,v,w
   integer, parameter :: maxSubPixels = 32
   double precision :: x0,y0,z0,u0,v0,w0
   double precision, dimension(NLTEspec%Nwaves) :: Iold, nu, I0, I0c
   double precision, dimension(:,:), allocatable :: QUV
   double precision, dimension(3) :: sdx, sdy
   double precision:: npix2, diff
   double precision, parameter :: precision = 1.e-2
   integer :: i, j, subpixels, iray, ri, zj, phik, icell, iter
   logical :: lintersect, labs

   labs = .false.
   ! reset local Fluxes
   I0c = 0d0
   I0 = 0d0
   if (atmos%magnetized) then 
    if (.not.allocated(QUV)) allocate(QUV(3,NLTEspec%Nwaves)) 
    !anyway set to 0 each time we enter the routine
    QUV(:,:) = 0d0
   end if
   ! Ray tracing : on se propage dans l'autre sens
   u0 = -u ; v0 = -v ; w0 = -w

   ! le nbre de subpixel en x est 2^(iter-1)
   subpixels = 1
   iter = 1

   infinie : do ! Boucle infinie tant que le pixel n'est pas converge
     npix2 =  real(subpixels)**2
     Iold = I0
     I0 = 0d0
     I0c = 0d0
     ! Vecteurs definissant les sous-pixels
     sdx(:) = dx(:) / real(subpixels,kind=dp)
     sdy(:) = dy(:) / real(subpixels,kind=dp)

     iray = 1 ! because the direction is fixed and we compute the flux emerging
               ! from a pixel, by computing the Intensity in this pixel

     ! L'obs est en dehors de la grille
     ri = 2*n_rad ; zj=1 ; phik=1

     ! Boucle sur les sous-pixels qui calcule l'intensite au centre
     ! de chaque sous pixel
     do i = 1,subpixels
        do j = 1,subpixels
           ! Centre du sous-pixel
           x0 = pixelcorner(1) + (i - 0.5_dp) * sdx(1) + (j-0.5_dp) * sdy(1)
           y0 = pixelcorner(2) + (i - 0.5_dp) * sdx(2) + (j-0.5_dp) * sdy(2)
           z0 = pixelcorner(3) + (i - 0.5_dp) * sdx(3) + (j-0.5_dp) * sdy(3)
           ! On se met au bord de la grille : propagation a l'envers
           !write(*,*) x0, y0, z0
           CALL move_to_grid(id, x0,y0,z0,u0,v0,w0, icell,lintersect)
           if (lintersect) then ! On rencontre la grille, on a potentiellement du flux
           !write(*,*) i, j, lintersect, labs, n_cells, icell
             CALL INTEG_RAY_LINE(id, icell, x0,y0,z0,u0,v0,w0,iray,labs)
             I0 = I0 + NLTEspec%I(:,iray,id)
             I0c = I0c + NLTEspec%Ic(:,iray,id)
             if (atmos%magnetized) QUV(3,:) = QUV(3,:) + NLTEspec%STokesV(:,iray,id)
           !else !Outside the grid, no radiation flux
           endif
        end do !j
     end do !i

     I0 = I0 / npix2
     I0c = I0c / npix2

     if (iter < n_iter_min) then
        ! On itere par defaut
        subpixels = subpixels * 2
     else if (iter >= n_iter_max) then
        ! On arrete pour pas tourner dans le vide
        ! write(*,*) "Warning : converging pb in ray-tracing"
        ! write(*,*) " Pixel", ipix, jpix
        exit infinie
     else
        ! On fait le test sur a difference
        diff = maxval( abs(I0 - Iold) / (I0 + 1e-300_dp) )
        if (diff > precision ) then
           ! On est pas converge
           subpixels = subpixels * 2
        else
           exit infinie
        end if
     end if ! iter
     iter = iter + 1
   end do infinie

  !Prise en compte de la surface du pixel (en sr)

  nu = 1d0 !c_light / NLTEspec%lambda * 1d9 !to get W/m2 instead of W/m2/Hz !in Hz
  ! Flux out of a pixel in W/m2/Hz
  I0 = nu * I0 * (pixelsize / (distance*pc_to_AU) )**2
  I0c = nu * I0c * (pixelsize / (distance*pc_to_AU) )**2
  if (atmos%magnetized) then 
   QUV(1,:) = QUV(1,:) * nu * (pixelsize / (distance*pc_to_AU) )**2
   QUV(2,:) = QUV(2,:) * nu * (pixelsize / (distance*pc_to_AU) )**2
   QUV(3,:) = QUV(3,:) * nu * (pixelsize / (distance*pc_to_AU) )**2
  end if

  ! adding to the total flux map.
  if (RT_line_method==1) then
    NLTEspec%Flux(:,1,1,ibin,iaz) = NLTEspec%Flux(:,1,1,ibin,iaz) + I0
    NLTEspec%Fluxc(:,1,1,ibin,iaz) = NLTEspec%Fluxc(:,1,1,ibin,iaz) + I0c
  else
    NLTEspec%Flux(:,ipix,jpix,ibin,iaz) = I0
    NLTEspec%Fluxc(:,ipix,jpix,ibin,iaz) = I0c
    if (atmos%magnetized) NLTEspec%F_QUV(:,:,ipix,jpix,ibin,iaz) = QUV(:,:)
  end if

  RETURN
  END SUBROUTINE FLUX_PIXEL_LINE

 SUBROUTINE EMISSION_LINE_MAP(ibin,iaz)
 ! -------------------------------------------------------------- !
  ! Line emission map in a given direction n(ibin,iaz),
  ! using ray-tracing.
  ! if only one pixel it gives the total Flux.
  ! See: emission_line_map in mol_transfer.f90
 ! -------------------------------------------------------------- !
  integer, intent(in) :: ibin, iaz !define the direction in which the map is computed
  double precision :: x0,y0,z0,l,u,v,w

  double precision, dimension(3) :: uvw, x_plan_image, x, y_plan_image, center, dx, dy, Icorner
  double precision, dimension(3,nb_proc) :: pixelcorner
  double precision:: taille_pix, nu
  integer :: i,j, id, npix_x_max, n_iter_min, n_iter_max

  integer, parameter :: n_rad_RT = 100, n_phi_RT = 36
  integer, parameter :: n_ray_star = 1000
  double precision, dimension(n_rad_RT) :: tab_r
  double precision:: rmin_RT, rmax_RT, fact_r, r, phi, fact_A, cst_phi
  integer :: ri_RT, phi_RT, lambda, lM, lR, lB, ll
  logical :: lresolved

  write(*,*) "incl (deg) = ", tab_RT_incl(ibin), "azimuth (deg) = ", tab_RT_az(iaz)

  u = tab_u_RT(ibin,iaz) ;  v = tab_v_RT(ibin,iaz) ;  w = tab_w_RT(ibin)
  uvw = (/u,v,w/) !vector position
  write(*,*) "u=", u*rad_to_deg, "v=",v*rad_to_deg, "w=",w*rad_to_deg

  ! Definition des vecteurs de base du plan image dans le repere universel
  ! Vecteur x image sans PA : il est dans le plan (x,y) et orthogonal a uvw
  x = (/cos(tab_RT_az(iaz) * deg_to_rad),sin(tab_RT_az(iaz) * deg_to_rad),0._dp/)

  ! Vecteur x image avec PA
  if (abs(ang_disque) > tiny_real) then
     ! Todo : on peut faire plus simple car axe rotation perpendiculaire a x
     x_plan_image = rotation_3d(uvw, ang_disque, x)
  else
     x_plan_image = x
  endif

  ! Vecteur y image avec PA : orthogonal a x_plan_image et uvw
  y_plan_image = -cross_product(x_plan_image, uvw)

  ! position initiale hors modele (du cote de l'observateur)
  ! = centre de l'image
  l = 10.*Rmax  ! on se met loin ! in AU

  x0 = u * l  ;  y0 = v * l  ;  z0 = w * l
  center(1) = x0 ; center(2) = y0 ; center(3) = z0

  ! Coin en bas gauche de l'image
  Icorner(:) = center(:) - 0.5 * map_size * (x_plan_image + y_plan_image)

  if (RT_line_method==1) then !log pixels
    n_iter_min = 1
    n_iter_max = 1

    ! dx and dy are only required for stellar map here
    taille_pix = (map_size/zoom)  ! en AU
    dx(:) = x_plan_image * taille_pix
    dy(:) = y_plan_image * taille_pix

    i = 1
    j = 1
    lresolved = .false.

    rmin_RT = max(w*0.9_dp,0.05_dp) * Rmin
    rmax_RT = 2.0_dp * Rmax

    tab_r(1) = rmin_RT
    fact_r = exp( (1.0_dp/(real(n_rad_RT,kind=dp) -1))*log(rmax_RT/rmin_RT) )

    do ri_RT = 2, n_rad_RT
      tab_r(ri_RT) = tab_r(ri_RT-1) * fact_r
    enddo

    fact_A = sqrt(pi * (fact_r - 1.0_dp/fact_r)  / n_phi_RT )

    ! Boucle sur les rayons d'echantillonnage
    !$omp parallel &
    !$omp default(none) &
    !$omp private(ri_RT,id,r,taille_pix,phi_RT,phi,pixelcorner) &
    !$omp shared(tab_r,fact_A,x_plan_image,y_plan_image,center,dx,dy,u,v,w,i,j) &
    !$omp shared(n_iter_min,n_iter_max,l_sym_ima,cst_phi,ibin,iaz)
    id =1 ! pour code sequentiel

    if (l_sym_ima) then
      cst_phi = pi  / real(n_phi_RT,kind=dp)
    else
      cst_phi = deux_pi  / real(n_phi_RT,kind=dp)
    endif

     !$omp do schedule(dynamic,1)
     do ri_RT=1, n_rad_RT
        !$ id = omp_get_thread_num() + 1

        r = tab_r(ri_RT)
        taille_pix =  fact_A * r ! racine carree de l'aire du pixel

        do phi_RT=1,n_phi_RT ! de 0 a pi
           phi = cst_phi * (real(phi_RT,kind=dp) -0.5_dp)
           pixelcorner(:,id) = center(:) + r * sin(phi) * x_plan_image + r * cos(phi) * y_plan_image
            ! C'est le centre en fait car dx = dy = 0.
           CALL FLUX_PIXEL_LINE(id,ibin,iaz,n_iter_min,n_iter_max, &
                      i,j,pixelcorner(:,id),taille_pix,dx,dy,u,v,w)
        end do !j
     end do !i
     !$omp end do
     !$omp end parallel
  else !method 2
     ! Vecteurs definissant les pixels (dx,dy) dans le repere universel
     taille_pix = (map_size/zoom) / real(max(npix_x,npix_y),kind=dp) ! en AU
     lresolved = .true.

     dx(:) = x_plan_image * taille_pix
     dy(:) = y_plan_image * taille_pix

     if (l_sym_ima) then
        npix_x_max = npix_x/2 + modulo(npix_x,2)
     else
        npix_x_max = npix_x
     endif

     !$omp parallel &
     !$omp default(none) &
     !$omp private(i,j,id) &
     !$omp shared(Icorner,pixelcorner,dx,dy,u,v,w,taille_pix,npix_x_max,npix_y) &
     !$omp shared(n_iter_min,n_iter_max,ibin,iaz)

     ! loop on pixels
     id = 1 ! pour code sequentiel
     n_iter_min = 1 ! 3
     n_iter_max = 1 ! 6

     !$omp do schedule(dynamic,1)
     do i = 1,npix_x_max
        !$ id = omp_get_thread_num() + 1
        do j = 1,npix_y
           !write(*,*) i,j
           ! Coin en bas gauche du pixel
           pixelcorner(:,id) = Icorner(:) + (i-1) * dx(:) + (j-1) * dy(:)
           CALL FLUX_PIXEL_LINE(id,ibin,iaz,n_iter_min,n_iter_max, &
                      i,j,pixelcorner(:,id),taille_pix,dx,dy,u,v,w)
        enddo !j
     enddo !i
     !$omp end do
     !$omp end parallel

  end if

  write(*,*) " -> Adding stellar flux"
  do lambda = 1, NLTEspec%Nwaves
   nu = c_light / NLTEspec%lambda(lambda) * 1d9 !if NLTEspec%Flux in W/m2 set nu = 1d0 Hz
                                             !else it means that in FLUX_PIXEL_LINE, nu
                                             !is 1d0 (to have flux in W/m2/Hz)
   CALL compute_stars_map(lambda, u, v, w, taille_pix, dx, dy, lresolved)
   NLTEspec%Flux(lambda,:,:,ibin,iaz) =  NLTEspec%Flux(lambda,:,:,ibin,iaz) +  &
                                         stars_map(:,:,1) / nu
   NLTEspec%Fluxc(lambda,:,:,ibin,iaz) = NLTEspec%Fluxc(lambda,:,:,ibin,iaz) + &
                                         stars_map_cont(:,:,1) / nu
  end do

 RETURN
 END SUBROUTINE EMISSION_LINE_MAP

 ! NOTE: should inverse the order of frequencies and depth because in general
 !       n_cells >> n_lambda, in "real" cases.

 SUBROUTINE Atomic_transfer()
 ! --------------------------------------------------------------------------- !
  ! This routine initialises the necessary quantities for atomic line transfer
  ! and calls the appropriate routines for LTE or NLTE transfer.
 ! --------------------------------------------------------------------------- !
  integer :: atomunit = 1, nact
  integer :: icell
  integer :: ibin, iaz
  character(len=20) :: ne_start_sol = "H_IONISATION"
  logical :: lwrite_waves = .false.

#include "sprng_f.h"

  optical_length_tot => atom_optical_length_tot
  if (.not.associated(optical_length_tot)) then
   write(*,*) "pointer optical_length_tot not associated"
   stop
  end if

  if (npix_x_save > 1) then
   RT_line_method = 2 ! creation d'une carte avec pixels carres
   npix_x = npix_x_save ; npix_y = npix_y_save
  else
   RT_line_method = 1 !pixels circulaires
  end if

  !read in dust_transfer.f90 in case of -pluto.
  !mainly because, RT atomic line and dust RT are not decoupled
  !move elsewhere, in the model reading/definition?
!! ----------------------- Read Model ---------------------- !!
  if (.not.lpluto_file) CALL magneto_accretion_model()  
!! --------------------------------------------------------- !!
  !Read atomic models and allocate space for n, nstar, vbroad, ntotal, Rij, Rji
  ! on the whole grid space.
  ! The following routines have to be invoked in the right order !
  CALL readAtomicModels(atomunit)

  if (atmos%Nactiveatoms>0) then
  write(*,*) "Beware, pops in background Hydrogen opacities uses n instead of nstar"
  write(*,*) "There will be a bug if H is active, as n is not an alias to nstar in this case"
  write(*,*) "also in solve NE."
  !if I set atom%n to atom%nstar before starting the NLTE loop
  !independently of the starting solution, solvene and background H should work
  !properly. And then I set atom%n to the initial guess and starts the NLTEloop, with
  !eventually iteration of the electron density
  stop
  !or at the forst iteration set atmos%Atoms(nll)%ptr_atom%NLTEpops = .false. (normally true
  !if the atom is active (or is passive but pops read from file,s that %n and %nstar are different).
  !If we do that for the first iteration, ne is computed using kurucz pf. 
  !then we can set atmos%Atoms(nll)%ptr_atom%NLTEpops = true again and NLTE pops will be used.
  atmos%Atoms(nact)%ptr_atom%NLTEpops = .false.
  
  end if
  ! if the electron density is not provided by the model or simply want to
  ! recompute it
  ! if atmos%ne given, but one want to recompute ne
  ! else atmos%ne not given, its computation is mandatory
  ! if NLTE pops are read in readAtomicModels, H%n(Nlevel,:) and atom%n
  !can be used for the electron density calculation.
  if (.not.atmos%calc_ne) atmos%calc_ne = lsolve_for_ne
  if (lsolve_for_ne) write(*,*) "(Force) Solving for electron density"
  if (atmos%calc_ne) then
   if (lsolve_for_ne) write(*,*) "(Force) Solving for electron density"
   if (.not.lsolve_for_ne) write(*,*) "Solving for electron density"
   write(*,*) " Starting solution : ", ne_start_sol
   if ((ne_start_sol == "NE_MODEL") .and. (atmos%calc_ne)) then
    write(*,*) "WARNING, ne from model is presumably 0 (or not given)."
    write(*,*) "Changing ne starting solution NE_MODEL in H_IONISATION"
    ne_start_sol = "H_IONISATION"
   end if
   CALL SolveElectronDensity(ne_start_sol)
   CALL writeElectron()
  end if
  CALL writeHydrogenDensity()
  CALL setLTEcoefficients () !write pops at the end because we probably have NLTE pops also
  !set Hydrogen%n = Hydrogen%nstar for the background opacities calculations.
!! --------------------------------------------------------- !!
  NLTEspec%atmos => atmos !this one is important because atmos_type : atmos is not used.
!   allocate(NLTEspec%lambda(1000))
!   NLTEspec%lambda(1) = 50d0
!   do icell=2, 1000
!    NLTEspec%lambda(icell) = NLTEspec%lambda(icell-1) + (800d0 - 50d0)/(1000d0-1d0)
!   end do
  CALL initSpectrum(lam0=500d0,vacuum_to_air=lvacuum_to_air,write_wavelength=lwrite_waves)
  CALL allocSpectrum()
  if (lstore_opac) then !o nly Background lines and active transitions
                                         ! chi and eta, are computed on the fly.
                                         ! Background continua (=ETL) are kept in memory.
   if (real(3*n_cells*NLTEspec%Nwaves)/(1024**3) < 1.) then
    write(*,*) "Keeping", real(3*n_cells*NLTEspec%Nwaves)/(1024**2), " MB of memory", &
   	 " for Background continuum opacities."
   else
    write(*,*) "Keeping", real(3*n_cells*NLTEspec%Nwaves)/(1024**3), " GB of memory", &
   	 " for Background continuum opacities."
   end if
   !!To DO: keep line LTE opacities if lstatic
   !$omp parallel &
   !$omp default(none) &
   !$omp private(icell) &
   !$omp shared(atmos)
   !$omp do
   do icell=1,atmos%Nspace
    CALL BackgroundContinua(icell)
   end do
   !$omp end do
   !$omp end parallel
   !!!TO DO:
   ! At the end of NLTE transfer keep active continua in memory for images
   !just like background conitua, avoiding te recompute them as they do not change
   !! TDO DO2: try to keep lines opac also.
  end if

  ! ----- ALLOCATE SOME MCFOST'S INTRINSIC VARIABLES NEEDED FOR AL-RT ------!
  CALL reallocate_mcfost_vars()

  ! --- END ALLOCATING SOME MCFOST'S INTRINSIC VARIABLES NEEDED FOR AL-RT --!
  !start transfer
  if (atmos%Nactiveatoms > 0) CALL NLTEloop(0, 1d-4)
  
  write(*,*) "Computing emission flux map..."
  !Use converged NLTEOpac
  do ibin=1,RT_n_incl
     do iaz=1,RT_n_az
       CALL EMISSION_LINE_MAP(ibin,iaz)
     end do
  end do
  CALL WRITE_FLUX()

 ! Transfer ends, save data, free some space and leave
 !should be closed after reading ? no if we do not save the C matrix in each cells
 !CALL WRITEATOM()
 CALL freeSpectrum() !deallocate spectral variables
 CALL free_atomic_atmos()
 deallocate(ds)
 NULLIFY(optical_length_tot)

 RETURN
 END SUBROUTINE
 
 SUBROUTINE NLTEloop(Niter, IterLim)
  integer, intent(in) :: Niter
  double precision, intent(in) :: IterLim
  integer :: atomunit = 1, nact
  integer :: icell
  integer :: ibin, iaz
  character(len=20) :: ne_start_sol = "NE_MODEL" !iterate from the starting guess

  

  !! --------------------- NLTE--------------------------------- !!
  !! For NLTE do not forget ->
  !initiate NLTE popuplations for ACTIVE atoms, depending on the choice of the solution
  ! CALL initialSol()
  ! for now initialSol() is replaced by this if loop on active atoms
  if (atmos%Nactiveatoms > 0) then
    write(*,*) "solving for ", atmos%Nactiveatoms, " active atoms"
    do nact=1,atmos%Nactiveatoms
     atmos%Atoms(nact)%ptr_atom%NLTEpops = .true. !again
     write(*,*) "Setting initial solution for active atom ", atmos%ActiveAtoms(nact)%ptr_atom%ID, &
      atmos%ActiveAtoms(nact)%ptr_atom%active
     atmos%ActiveAtoms(nact)%ptr_atom%n = 1d0 * atmos%ActiveAtoms(nact)%ptr_atom%nstar
     CALL allocNetCoolingRates(atmos%ActiveAtoms(nact)%ptr_atom)
    end do
  end if !end replacing initSol()
!   ! Read collisional data and fill collisional matrix C(Nlevel**2) for each ACTIVE atoms.
!   ! Initialize at C=0.0 for each cell points.
!   ! the matrix is allocated for ACTIVE atoms only in setLTEcoefficients and the file open
!   ! before the transfer starts and closed at the end.
!   do nact=1,atmos%Nactiveatoms
!     if (atmos%ActiveAtoms(nact)%active) then
!      CALL CollisionRate(icell, atmos%ActiveAtoms(nact))
!      CALL initGamma(icell, atmos%ActiveAtoms(nact)) !set Gamma to C for each active atom
!       !note that when updating populations, if ne is kept fixed (and T and nHtot etc)
!       !atom%C is fixed, therefore we only use initGamma. If they chane, call CollisionRate() again
!      end if
!   end do
!   if (atmos%Nrays==1) then !placed before computing J etc
!    write(*,*) "Solving for", atmos%Nrays,' direction.'
!   else
!    write(*,*) "Solving for", atmos%Nrays,' directions.'
!   end if
!
!! -------------------------------------------------------- !!

 do nact=1,atmos%Nactiveatoms
  CALL closeCollisionFile(atmos%ActiveAtoms(nact)%ptr_atom) !if opened
 end do

 
 RETURN
 END SUBROUTINE NLTEloop

 SUBROUTINE reallocate_mcfost_vars()
  !--> should move them to init_atomic_atmos ? or elsewhere
  !need to be deallocated at the end of molecule RT or its okey ?`
  integer :: la
  if (allocated(ds)) deallocate(ds)
  allocate(ds(atmos%Nrays,NLTEspec%NPROC))
  ds = 0d0 !meters
  CALL init_directions_ray_tracing()
  if (.not.allocated(stars_map)) allocate(stars_map(npix_x,npix_y,3))
  if (.not.allocated(stars_map_cont)) allocate(stars_map_cont(npix_x,npix_y,3))
  n_lambda = NLTEspec%Nwaves
  if (allocated(tab_lambda)) deallocate(tab_lambda)
  allocate(tab_lambda(n_lambda))
  if (allocated(tab_delta_lambda)) deallocate(tab_delta_lambda)
  allocate(tab_delta_lambda(n_lambda))
  tab_lambda = NLTEspec%lambda / MICRON_TO_NM
  tab_delta_lambda(1) = 0d0
  do la=2,NLTEspec%Nwaves
   tab_delta_lambda(la) = tab_lambda(la) - tab_lambda(la-1)
  end do
  if (allocated(tab_lambda_inf)) deallocate(tab_lambda_inf)
  allocate(tab_lambda_inf(n_lambda))
  if (allocated(tab_lambda_sup)) deallocate(tab_lambda_sup)
  allocate(tab_lambda_sup(n_lambda))
  tab_lambda_inf = tab_lambda
  tab_lambda_sup = tab_lambda_inf + tab_delta_lambda
  ! computes stellar flux at the new wavelength points
  CALL deallocate_stellar_spectra()
  if (allocated(kappa)) deallocate(kappa) !do not use it anymore
  !used for star map ray-tracing.
  CALL allocate_stellar_spectra(n_lambda)
  CALL repartition_energie_etoiles()
  !If Vfield is used in atomic line transfer, with lkep or linfall
  !atmos%Vxyz is not used and lmagnetoaccr is supposed to be zero
  !and Vfield allocated and filled in the model definition if not previously allocated
  !nor filled.
  if (allocated(Vfield).and.lkeplerian.or.linfall) then
    write(*,*) "Vfield max/min", maxval(Vfield), minval(Vfield)
  else if (allocated(Vfield).and.lmagnetoaccr) then
   write(*,*) "deallocating Vfield for atomic lines when lmagnetoaccr = .true."
   deallocate(Vfield)
  end if

 RETURN
 END SUBROUTINE reallocate_mcfost_vars

END MODULE AtomicTransfer
