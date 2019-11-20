! ---------------------------------------------------------------------- !
! This module writes to separate files the populations of each atom.
! - n
! - nHtot
! - nH-
!
! TO DO:  
!      - check points
!      - read electrons density
!
! Atomic data are written to atom%dataFile
! Electronic density is also written in a separate file
! ---------------------------------------------------------------------- !
MODULE writeatom !Futur write_atomic_pops

 use atmos_type, only : atmos
 use atom_type
 use spectrum_type

 !MCFOST's original modules
 use fits_utils, only : print_error
 use grid
 use utils, only : appel_syst
 use messages

 IMPLICIT NONE

 !Compressed files may only be opened with read-only permission
 ! So if ne is iterated we re open ne.fits to write the nlte pops, so It cannot be
 ! compressed.
 !
 !
 character(len=15), parameter :: neFile = "ne.fits"
 character(len=15), parameter :: nHminFile = "nHmin.fits"
 character(len=15), parameter :: nHFile = "nHtot.fits.gz"

 integer, parameter :: Nmax_kept_iter = 1 !keep the Nmax_kept_iter latest iterations.
 !the first is the oldest one


 CONTAINS

 SUBROUTINE writeIteration()


 RETURN
 END SUBROUTINE writeIteration

 SUBROUTINE make_checkpoint()

 RETURN
 END SUBROUTINE make_checkpoint

 SUBROUTINE writeElectron(write_ne_nlte)
 ! ------------------------------------ !
 ! write Electron density if computed
 ! by the code.
 ! The electron density, ne, is in m^-3
 ! ------------------------------------ !
  integer :: unit, EOF = 0, blocksize, naxes(4), naxis,group, bitpix, fpixel
  logical :: extend, simple, already_exists = .false.
  logical, optional :: write_ne_nlte
  integer :: nelements, nfirst

  if (present(write_ne_nlte)) already_exists = write_ne_nlte !append the file
  !get unique unit number
  CALL ftgiou(unit,EOF)
  blocksize=1
  simple = .true. !Standard fits
  group = 1 !??
  fpixel = 1
  extend = .true.
  bitpix = -64

  if (lVoronoi) then
   	naxis = 1
   	naxes(1) = atmos%Nspace ! equivalent n_cells
   	nelements = naxes(1)
  else
   	if (l3D) then
    	naxis = 3
    	naxes(1) = n_rad
   	 	naxes(2) = 2*nz
    	naxes(3) = n_az
    	nelements = naxes(1) * naxes(2) * naxes(3) ! != n_cells ? should be
   	else
    	naxis = 2
    	naxes(1) = n_rad
    	naxes(2) = nz
    	nelements = naxes(1) * naxes(2) ! should be n_cells also
   	end if
  end if
  ! write(*,*) 'yoyo2', n_rad, nz, n_cells, atmos%Nspace
  !  Write the required header keywords.

  if (already_exists) then !exits, expect to write nlte, read lte ne, append the file and write
  	CALL ftopen(unit, TRIM(neFile), 1, blocksize, EOF) !1 stends for read and write
  	!Compressed files may only be opened with read-only permission, so neFile is not .gz
   	CALL ftcrhd(unit, EOF)
   	CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
  	CALL ftpkys(unit, "UNIT", "m^-3", '(NLTE)', EOF)
  	CALL ftpprd(unit,group,fpixel,nelements,atmos%ne,EOF)
  else !not exist, expected not nlte, create and write
  	CALL ftinit(unit,trim(neFile),blocksize,EOF)
  !  Initialize parameters about the FITS image
  	CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
  ! Additional optional keywords
  	CALL ftpkys(unit, "UNIT", "m^-3", ' ', EOF)
  !write data
  	CALL ftpprd(unit,group,fpixel,nelements,atmos%ne,EOF)
  end if !alreayd_exists

  CALL ftclos(unit, EOF)
  CALL ftfiou(unit, EOF)

  if (EOF > 0) CALL print_error(EOF)

 RETURN
 END SUBROUTINE writeElectron

 SUBROUTINE writeHydrogenDensity()
 ! ------------------------------------ !
 ! write nHtot density m^-3
 ! ------------------------------------ !
  integer :: unit, EOF = 0, blocksize, naxes(4), naxis,group, bitpix, fpixel
  logical :: extend, simple
  integer :: nelements

  !get unique unit number
  CALL ftgiou(unit,EOF)

  blocksize=1
  CALL ftinit(unit,trim(nHFile),blocksize,EOF)
  !  Initialize parameters about the FITS image
  simple = .true. !Standard fits
  group = 1 !??
  fpixel = 1
  extend = .false. !??
  bitpix = -64

  if (lVoronoi) then
   naxis = 1
   naxes(1) = atmos%Nspace ! equivalent n_cells
   nelements = naxes(1)
  else
   if (l3D) then
    naxis = 3
    naxes(1) = n_rad
    naxes(2) = 2*nz
    naxes(3) = n_az
    nelements = naxes(1) * naxes(2) * naxes(3) ! != n_cells ? should be
   else
    naxis = 2
    naxes(1) = n_rad
    naxes(2) = nz
    nelements = naxes(1) * naxes(2) ! should be n_cells also
   end if
  end if
  ! write(*,*) 'yoyo2', n_rad, nz, n_cells, atmos%Nspace
  !  Write the required header keywords.

  CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
  ! Additional optional keywords
  CALL ftpkys(unit, "UNIT", "m^-3", ' ', EOF)
  !write data
  CALL ftpprd(unit,group,fpixel,nelements,atmos%nHtot,EOF)

  CALL ftclos(unit, EOF)
  CALL ftfiou(unit, EOF)

  if (EOF > 0) CALL print_error(EOF)

 RETURN
 END SUBROUTINE writeHydrogenDensity

 SUBROUTINE writeHydrogenMinusDensity(write_nHmin_nlte)
 ! ------------------------------------ !
 ! write H- density.
 ! ------------------------------------ !
  integer :: unit, EOF = 0, blocksize, naxes(4), naxis,group, bitpix, fpixel
  logical :: extend, simple, already_exists = .false.
  logical, optional :: write_nHmin_nlte
  integer :: nelements, nfirst

  if (present(write_nHmin_nlte)) already_exists = write_nHmin_nlte !append the file
  !get unique unit number
  CALL ftgiou(unit,EOF)
  blocksize=1
  simple = .true. !Standard fits
  group = 1 !??
  fpixel = 1
  extend = .true.
  bitpix = -64

  if (lVoronoi) then
   	naxis = 1
   	naxes(1) = atmos%Nspace ! equivalent n_cells
   	nelements = naxes(1)
  else
   	if (l3D) then
    	naxis = 3
    	naxes(1) = n_rad
   	 	naxes(2) = 2*nz
    	naxes(3) = n_az
    	nelements = naxes(1) * naxes(2) * naxes(3) ! != n_cells ? should be
   	else
    	naxis = 2
    	naxes(1) = n_rad
    	naxes(2) = nz
    	nelements = naxes(1) * naxes(2) ! should be n_cells also
   	end if
  end if
  ! write(*,*) 'yoyo2', n_rad, nz, n_cells, atmos%Nspace
  !  Write the required header keywords.

  if (already_exists) then !exits, expect to write nlte, read lte ne, append the file and write
  	CALL ftopen(unit, TRIM(nHminFile), 1, blocksize, EOF) !1 stends for read and write
  	!Compressed files may only be opened with read-only permission, so neFile is not .gz
   	CALL ftcrhd(unit, EOF)
   	CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
  	CALL ftpkys(unit, "UNIT", "m^-3", '(NLTE)', EOF)
  	CALL ftpprd(unit,group,fpixel,nelements,atmos%nHmin,EOF)
  else !not exist, expected not nlte, create and write
  	CALL ftinit(unit,trim(nHminFile),blocksize,EOF)
  !  Initialize parameters about the FITS image
  	CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
  ! Additional optional keywords
  	CALL ftpkys(unit, "UNIT", "m^-3", ' ', EOF)
  !write data
  	CALL ftpprd(unit,group,fpixel,nelements,atmos%nHmin,EOF)
  end if !alreayd_exists

  CALL ftclos(unit, EOF)
  CALL ftfiou(unit, EOF)

  if (EOF > 0) CALL print_error(EOF)

 RETURN
 END SUBROUTINE writeHydrogenMinusDensity

 
 SUBROUTINE writePops(atom)
 ! ----------------------------------------------------------------- !
 ! write Atom populations. The file for writing exists already
 ! First, NLTE populations, then LTE populations.
 ! ----------------------------------------------------------------- !
  type (AtomType), intent(in) :: atom
  integer :: unit, EOF = 0, blocksize, naxes(5), naxis,group, bitpix, fpixel
  logical :: extend, simple, lte_only
  integer :: nelements, hdutype, status
  character(len=20) :: popsF

  lte_only = .not.atom%active
  
  !get unique unit number
  CALL ftgiou(unit,EOF)
  blocksize=1
  simple = .true. !Standard fits
  group = 1 !??
  fpixel = 1
  extend = .true.
  bitpix = -64
  
  CALL ftinit(unit, TRIM(atom%dataFile), blocksize, EOF)

  naxes(1) = atom%Nlevel

  if (lVoronoi) then
   naxis = 2
   naxes(2) = atmos%Nspace ! equivalent n_cells
   nelements = naxes(1)*naxes(2)
  else
   if (l3D) then
    naxis = 4
    naxes(2) = n_rad
    naxes(3) = 2*nz
    naxes(4) = n_az
    nelements = naxes(1) * naxes(2) * naxes(3) * naxes(4)
   else
    naxis = 3
    naxes(2) = n_rad
    naxes(3) = nz
    nelements = naxes(1) * naxes(2) * naxes(3)
   end if
  end if
  


   if (lte_only) then
  
    CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
    ! Additional optional keywords
    CALL ftpkys(unit, "UNIT", "m^-3", "(LTE)", EOF)
    !write data
    CALL ftpprd(unit,group,fpixel,nelements,atom%nstar,EOF)
   else !NLTE + LTE
    CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
    ! Additional optional keywords
    CALL ftpkys(unit, "UNIT", "m^-3", "(NLTE)", EOF)
    !write data
    CALL ftpprd(unit,group,fpixel,nelements,atom%n,EOF)
    
    CALL ftcrhd(unit, status)
    if (status > 0) CALL print_error(status)

  
    CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
    ! Additional optional keywords
    CALL ftpkys(unit, "UNIT", "m^-3", "(LTE)", EOF)
    !write data
    CALL ftpprd(unit,group,fpixel,nelements,atom%nstar,EOF)
  	
   end if  


  CALL ftclos(unit, EOF) !close
  CALL ftfiou(unit, EOF) !free

  if (EOF > 0) CALL print_error(EOF)

 RETURN
 END SUBROUTINE writePops

 !---> need a debug
!  SUBROUTINE create_pops_file(atom)
!  ! Create file to write populations
!  !
!   type (AtomType), intent(inout) :: atom
!   logical :: lte_only
!   character(len=MAX_LENGTH) :: popsF, comment, iter_number
!   integer :: unit, EOF = 0, blocksize, naxes(5), naxis,group, bitpix, fpixel, i
!   logical :: extend, simple
!   integer :: nelements, syst_status, Nplus, N0
!   real(kind=dp), dimension(:), allocatable :: zero_arr
! 
! !    if (popsF(len(popsF)-3:len(popsF))==".gz") then
! !     CALL Warning("Atomic pops file cannot be compressed fits.")
! !     write(*,*) popsF, popsF(len(popsF)-3:len(popsF))
! !     atom%dataFile = popsF(1:len(popsF)-3)
! !     write(*,*) atom%dataFile
! !    end if
! 
!   lte_only = .not.atom%active
! 
!   !get unique unit number
!   CALL ftgiou(unit,EOF)
! 
!   blocksize=1
!   simple = .true. !Standard fits
!   group = 1
!   fpixel = 1
!   extend = .true.
!   bitpix = -64
! 
!   naxes(1) = atom%Nlevel
!   Nplus = 2 !lte + NLTE
!   if (lte_only) Nplus = 1
! 
!   N0 = max(1,Nmax_kept_iter) !at mini LTE, NLTE and last iteration atm
!   if (lte_only) N0 = 0
! 
!   if (lVoronoi) then
!    naxis = 2
!    naxes(2) = atmos%Nspace ! equivalent n_cells
!    nelements = naxes(1)*naxes(2)
!   else
!    if (l3D) then
!     naxis = 4
!     naxes(2) = n_rad
!     naxes(3) = 2*nz
!     naxes(4) = n_az
!     nelements = naxes(1) * naxes(2) * naxes(3) * naxes(4)
!    else
!     naxis = 3
!     naxes(2) = n_rad
!     naxes(3) = nz
!     nelements = naxes(1) * naxes(2) * naxes(3)
!    end if
!   end if
! 
!   allocate(zero_arr(nelements)); zero_arr=0d0
! 
!   CALL appel_syst('mkdir -p '//trim(atom%ID),syst_status) !create a dir for populations
!   CALL ftinit(unit,trim(atom%ID)//"/"//trim(atom%dataFile),blocksize,EOF)
! 
!   do i=1, N0 + Nplus
! 
!     write(iter_number, '(A10,I6,A1)') "(Iteration", i,")"
! 
!    	CALL ftcrhd(unit, EOF)
!    	CALL ftphpr(unit,simple,bitpix,naxis,naxes,0,1,extend,EOF)
! 
!    	COMMENT = trim(iter_number)
!    	if (lte_only) COMMENT = "(LTE)"
!    	if (i==Nmax_kept_iter+1) then
!    	 COMMENT = "(NLTE)"
!    	else if (i==Nmax_kept_iter+2) then
!    	 COMMENT = "(LTE)"
!    	end if
!   	CALL ftpkys(unit, "UNIT", "m^-3", COMMENT, EOF)
!     CALL ftpprd(unit,group,fpixel,nelements,zero_arr,EOF)
! 
!   end do
! 
!   deallocate(zero_arr)
! 
!   CALL ftclos(unit, EOF) !close
!   CALL ftfiou(unit, EOF) !free
! 
!   if (EOF > 0) CALL print_error(EOF)
!  RETURN
!  END SUBROUTINE create_pops_file
!  SUBROUTINE writePops(atom, count)
!  ! ----------------------------------------------------------------- !
!  ! write Atom populations. The file for writing exists already
!  ! First, NLTE populations, then LTE populations.
!  ! It is not a compressed file (.fits only)
!  ! so that populations after ith iteration can be
!  ! append to the file.
!  ! Keep in memory the three latest iterations
!  ! and overwrite them. At the end write the final
!  ! NLTE pops and then the LTE pops.
!  !
!  ! Contains:
!  !   1st oldest iter among the three last iter: count = 3
!  !   2nd 									  : count = 2
!  !   3rd youngest iter among the three last iter : count = 1
!  !      count = 0
!  !   atom%n converged (can be equal to atom%n(iter==3)
!  !   atom%nstar
!  !
!  !  count is decreasing
!  ! ----------------------------------------------------------------- !
!   type (AtomType), intent(inout) :: atom
!   integer, intent(in) :: count
!   integer :: unit, EOF = 0, blocksize, naxes(5), naxis,group, bitpix, fpixel
!   logical :: extend, simple, lte_only
!   integer :: nelements, syst_status, hdutype
!   character(len=20) :: popsF
! 
!   lte_only = .not.atom%active
!   if (count < 0) lte_only = .true. !force it in case it is active
! 
!   if (count > Nmax_kept_iter) RETURN
! 
!   !get unique unit number
!   CALL ftgiou(unit,EOF)
!   CALL ftopen(unit, TRIM(atom%dataFile), 1, blocksize, EOF) !1 stends for read and write
! 
!   blocksize=1
! 
!   !  Initialize parameters about the FITS image
!   simple = .true. !Standard fits
!   group = 1
!   fpixel = 1
!   extend = .true.
!   bitpix = -64
! 
!   naxes(1) = atom%Nlevel
! 
!   if (lVoronoi) then
!    naxis = 2
!    naxes(2) = atmos%Nspace ! equivalent n_cells
!    nelements = naxes(1)*naxes(2)
!   else
!    if (l3D) then
!     naxis = 4
!     naxes(2) = n_rad
!     naxes(3) = 2*nz
!     naxes(4) = n_az
!     nelements = naxes(1) * naxes(2) * naxes(3) * naxes(4)
!    else
!     naxis = 3
!     naxes(2) = n_rad
!     naxes(3) = nz
!     nelements = naxes(1) * naxes(2) * naxes(3)
!    end if
!   end if
! 
!   if (count>0) then !iterations
!     if (count <= Nmax_kept_iter) then
!     CALL FTMAHD(unit,count,hdutype,EOF)
!   	CALL ftpprd(unit,group,fpixel,nelements,atom%n,EOF)
!   	endif
!   else if (count<=0) then !final solutions + LTE
!    if (lte_only) then
!     CALL FTMAHD(unit,1,hdutype,EOF) !only one if lte_only
!   	CALL ftpprd(unit,group,fpixel,nelements,atom%nstar,EOF)
!    else !at least two
!     CALL FTMAHD(unit,Nmax_kept_iter+1,hdutype,EOF)
!   	CALL ftpprd(unit,group,fpixel,nelements,atom%n,EOF)
!     CALL FTMAHD(unit,Nmax_kept_iter+2,hdutype,EOF)
!   	CALL ftpprd(unit,group,fpixel,nelements,atom%nstar,EOF)
!    end if
!   end if
! 
!   CALL ftclos(unit, EOF) !close
!   CALL ftfiou(unit, EOF) !free
! 
!   if (EOF > 0) CALL print_error(EOF)
! 
!  RETURN
!  END SUBROUTINE writePops
!-> debug needed above

 SUBROUTINE readPops(atom)
 ! -------------------------------------------- !
 ! read Atom populations.
 ! First, NLTE populations, then LTE populations.
 ! -------------------------------------------- !
  type (AtomType), intent(in) :: atom
  integer :: unit, EOF = 0, blocksize, naxis,group, bitpix, fpixel
  logical :: extend, simple, anynull
  integer :: nelements, naxis2(4), Nl, naxis_found, hdutype
  character(len=256) :: some_comments

  !get unique unit number
  CALL ftgiou(unit,EOF)

  CALL ftopen(unit, trim(atom%ID)//"/"//TRIM(atom%dataFile), 0, blocksize, EOF)

  !move to the NiterationMAx+1 HDU
  CALL FTMAHD(unit,1,hdutype,EOF) !move to HDU, atom%n is first

  !  Initialize parameters about the FITS image
  simple = .true. !Standard fits
  group = 1
  fpixel = 1
  extend = .true.
  bitpix = -64

  if (lVoronoi) then
   naxis = 2
   CALL ftgknj(unit, 'NAXIS', 1, naxis, naxis2, naxis_found, EOF)
   CALL ftgkyj(unit, "NAXIS1", Nl, some_comments, EOF)
   if (Nl /= atom%Nlevel) CALL Error(" Nlevel read from file different from actual model!")
   nelements = Nl
   CALL ftgkyj(unit, "NAXIS2", naxis_found, some_comments, EOF)
   nelements = nelements * naxis_found
   if (nelements /= atom%Nlevel * atmos%Nspace) &
    CALL Error (" Model read does not match simulation box")
  else
   if (l3D) then
    naxis = 4
    CALL ftgknj(unit, 'NAXIS', 1, naxis, naxis2, naxis_found, EOF)
    !if (naxis2 /= naxis) CALL Error(" Naxis read from file different from actual model!")
    CALL ftgkyj(unit, "NAXIS1", Nl, some_comments, EOF)
    if (Nl /= atom%Nlevel) CALL Error(" Nlevel read from file different from actual model!")
    nelements = Nl
    CALL ftgkyj(unit, "NAXIS2", naxis_found, some_comments, EOF)
    nelements = nelements * naxis_found
    CALL ftgkyj(unit, "NAXIS3", naxis_found, some_comments, EOF)
    nelements = nelements * naxis_found
    CALL ftgkyj(unit, "NAXIS4", naxis_found, some_comments, EOF)
    nelements = nelements * naxis_found
    if (nelements /= atom%Nlevel * atmos%Nspace) &
    CALL Error (" Model read does not match simulation box")
   else
    naxis = 3
    CALL ftgknj(unit, 'NAXIS', 1, naxis, naxis2, naxis_found, EOF)
    CALL ftgkyj(unit, "NAXIS1", Nl, some_comments, EOF)
    if (Nl /= atom%Nlevel) CALL Error(" Nlevel read from file different from actual model!")
    nelements = Nl
    CALL ftgkyj(unit, "NAXIS2", naxis_found, some_comments, EOF)
    nelements = nelements * naxis_found
    CALL ftgkyj(unit, "NAXIS3", naxis_found, some_comments, EOF)
    nelements = nelements * naxis_found
    if (nelements /= atom%Nlevel * atmos%Nspace) &
    CALL Error (" Model read does not match simulation box")
   end if
  end if

  CALL FTG2Dd(unit,1,-999,shape(atom%n),atom%Nlevel,atmos%Nspace,atom%N,anynull,EOF)

  CALL ftclos(unit, EOF) !close
  CALL ftfiou(unit, EOF) !free

  if (EOF > 0) CALL print_error(EOF)

 RETURN
 END SUBROUTINE readPops


 !!!!!!!!!! BUILDING !!!!!!!!!!!!!!!
 SUBROUTINE readElectron(fileNe)
 ! ------------------------------------ !
 ! read Electron density from file
 ! ------------------------------------ !
  character(len=15), intent(in) :: fileNe
  integer :: EOF = 0, unit, blocksize, hdutype, anynull
  integer :: naxis, naxes(4)

  !get unique unit number
  CALL ftgiou(unit,EOF)
  ! open fits file in readmode'
  CALL ftopen(unit, TRIM(fileNe), 0, blocksize, EOF)

  CALL FTMAHD(unit,1,hdutype,EOF) !only one, the electron density
  if (lVoronoi) then
   CALL ftgkyj(unit, "NAXIS1", naxes(1), " ", EOF)
   if (naxes(1).ne.(atmos%Nspace)) then
      write(*,*) "Cannot read electron density (1)"
      RETURN
   end if
   RETURN !not implemented
  else
   if (l3D) then
    CALL ftgkyj(unit, "NAXIS1", naxes(1), " ", EOF)
    CALL ftgkyj(unit, "NAXIS2", naxes(2), " ", EOF)
    CALL ftgkyj(unit, "NAXIS3", naxes(3), " ", EOF)
    if ((naxes(1)*naxes(2)*naxes(3)).ne.(atmos%Nspace)) then
      write(*,*) "Cannot read electron density (2)"
      RETURN
    end if
    RETURN ! Not implemented
   else
    CALL ftgkyj(unit, "NAXIS1", naxes(1), " ", EOF)
    CALL ftgkyj(unit, "NAXIS2", naxes(2), " ", EOF)
    if ((naxes(1)*naxes(2)).ne.(atmos%Nspace)) then
      write(*,*) "Cannot read electron density (3)"
      RETURN
    end if
    CALL FTG2Dd(unit,1,-999,shape(atmos%ne),naxes(1),naxes(2),atmos%ne,anynull,EOF)
   end if
  end if
  CALL ftclos(unit, EOF)
  CALL ftfiou(unit, EOF)

  if (EOF > 0) CALL print_error(EOF)
 RETURN
 END SUBROUTINE readElectron

END MODULE writeatom
