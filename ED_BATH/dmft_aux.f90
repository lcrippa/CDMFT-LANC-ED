!+-------------------------------------------------------------------+
!PURPOSE  : Deallocate the ED bath
!+-------------------------------------------------------------------+
subroutine deallocate_dmft_bath()
   integer :: ibath,isym
   if(.not.dmft_bath%status)return
   do ibath=1,Nbath
      dmft_bath%item(ibath)%v = 0d0
      dmft_bath%item(ibath)%N_dec=0
      deallocate(dmft_bath%item(ibath)%lambda)
   enddo
   deallocate(dmft_bath%item)
   dmft_bath%status=.false.
end subroutine deallocate_dmft_bath



!+-------------------------------------------------------------------+
!PURPOSE  : Allocate the ED bath
!+-------------------------------------------------------------------+
subroutine allocate_dmft_bath()
   integer :: ibath,isym,Nsym
   !
   if(.not.allocated(lambda_impHloc))stop "lambda_impHloc not allocated in allocate_dmft_bath" !FIXME

   call deallocate_dmft_bath()
   !
   allocate(dmft_bath%item(Nbath))
   !
   !CHECK IF IDENDITY IS ONE OF THE SYMMETRIES, IF NOT ADD IT
   !Nsym=size(lambda_impHloc)+1
   !
   !do isym=1,size(lambda_impHloc)
   !   if(is_identity(H_Basis(isym)%O)) Nsym=Nsym-1
   !   exit
   !enddo
   Nsym=size(lambda_impHloc)
   !
   !ALLOCATE coefficients vectors
   !
   do ibath=1,Nbath
      dmft_Bath%item(ibath)%N_dec=Nsym
      allocate(dmft_bath%item(ibath)%lambda(Nsym))
   enddo
   !
   dmft_bath%status=.true.
end subroutine allocate_dmft_bath



!+-------------------------------------------------------------------+
!PURPOSE  : Reconstruct bath matrix from lambda vector
!+-------------------------------------------------------------------+

function bath_from_sym(lambdavec) result (Hbath)
   integer                                               :: Nsym,Nsym_,isym
   real(8),dimension(:)                                  :: lambdavec
   complex(8),dimension(Nlat,Nlat,Nspin,Nspin,Norb,Norb) :: Hbath
   !
   Nsym=size(lambdavec)
   Nsym_=size(lambda_impHloc)
   !
   Hbath=zero
   !
   do isym=1,Nsym_
      Hbath=Hbath+lambdavec(isym)*H_Basis(isym)%O
   enddo
   !
   !IF NO IDENTITY WAS DECLARED, ADD IT WITH THE OFFSET
   !
   !if(Nsym.ne.Nsym_)Hbath=Hbath+lso2nnn_reshape(lambdavec(Nsym_+1)*eye(Nlat*Nspin*Norb),Nlat,Nspin,Norb)
   !
end function bath_from_sym


!+------------------------------------------------------------------+
!PURPOSE  : Initialize the DMFT loop, builindg H parameters and/or 
!reading previous (converged) solution
!+------------------------------------------------------------------+
subroutine init_dmft_bath()
   real(8)                  :: re,im
   integer                  :: i,ibath,isym,unit,flen,Nh,Nsym,Nsym_
   integer,dimension(Nbath) :: Nlambdas
   integer                  :: io,jo,iorb,ispin,jorb,jspin
   logical                  :: IOfile
   real(8)                  :: de
   real(8)                  :: offset_b(Nbath),noise_b(Nlat*Nspin*Norb)
   character(len=21)        :: space
   !  
   if(.not.dmft_bath%status)stop "init_dmft_bath error: bath not allocated"
   !
   if(Nbath>1)then
      offset_b=linspace(-HWBAND,HWBAND,Nbath)
   else
      offset_b(1)=0.d0
   endif
   !
   !BATH V INITIALIZATION
   do ibath=1,Nbath
      dmft_bath%item(ibath)%v=max(0.1d0,1.d0/sqrt(dble(Nbath)))
   enddo
   !
   !BATH LAMBDAS INITIALIZATION
   do ibath=1,Nbath
      Nsym = dmft_bath%item(ibath)%N_dec
      Nsym_= size(lambda_impHloc)
      !if(Nsym .ne. Nsym_)then
         do isym=1,Nsym_
            dmft_bath%item(ibath)%lambda(isym) =  lambda_impHloc(isym)
         enddo
     !    dmft_bath%item(ibath)%lambda(Nsym_+1) =  -(xmu+offset_b(ibath))  !ADD THE OFFSET (IDENTITY)
     ! else
     !    do isym=1,Nsym
     !       dmft_bath%item(ibath)%lambda(isym) =  lambda_impHloc(isym)
     !       if(is_identity(H_basis(isym)%O)) dmft_bath%item(ibath)%lambda(isym) =&
     !          dmft_bath%item(ibath)%lambda(isym) - (xmu+offset_b(ibath))
     !    enddo
     ! endif
   enddo
   !
   !Read from file if exist:
   inquire(file=trim(Hfile)//trim(ed_file_suffix)//".restart",exist=IOfile)
   if(IOfile)then
      write(LOGfile,"(A)")"Reading bath from file "//trim(Hfile)//trim(ed_file_suffix)//".restart"
      unit = free_unit()
      flen = file_length(trim(Hfile)//trim(ed_file_suffix)//".restart")
      !
      open(unit,file=trim(Hfile)//trim(ed_file_suffix)//".restart")
      !
      !
      do ibath=1,Nbath
         !read number of lambdas
         read(unit,"(I3)")Nlambdas(ibath)
      enddo
      do ibath=1,Nbath
         !read V
         read(unit,"(F21.12,1X)")dmft_bath%item(ibath)%v
         !read lambdas
         read(unit,*)(dmft_bath%item(ibath)%lambda(jo),jo=1,Nlambdas(ibath))
      enddo
      close(unit)
   endif
end subroutine init_dmft_bath








!+-------------------------------------------------------------------+
!PURPOSE  : write out the bath to a given unit with 
! the following column formatting: 
! [(Ek_iorb,Vk_iorb)_iorb=1,Norb]_ispin=1,Nspin
!+-------------------------------------------------------------------+
subroutine write_dmft_bath(unit)
   integer,optional     :: unit
   integer              :: unit_
   integer              :: ibath
   integer              :: io,jo,iorb,ispin,isym
   complex(8)           :: hrep_aux_nnn(Nlat,Nlat,Nspin,Nspin,Norb,Norb)
   complex(8)           :: hrep_aux(Nlat*Nspin*Norb,Nlat*Nspin*Norb)
   character(len=64)    :: string_fmt,string_fmt_first
   !
   unit_=LOGfile;if(present(unit))unit_=unit
   if(.not.dmft_bath%status)stop "write_dmft_bath error: bath not allocated"
   !
   string_fmt_first="(F8.4,a5,"//str(Nlat*Nspin*Norb)//"(F8.4,1X),a5,"//str(Nlat*Nspin*Norb)//"(F8.4,1X))"
   string_fmt      ="(A8,a5,"//str(Nlat*Nspin*Norb)//"(F8.4,1X),a5,"//str(Nlat*Nspin*Norb)//"(F8.4,1X))"
   !
   if(unit_==LOGfile)then
      if(Nlat*Nspin*Norb.le.8)then
         write(unit_,"(A1)")" "
         write(unit_,"(A8,a3,a5,90(A15,1X))")"V","||"," ","Re(H) | Im(H)"        
         do ibath=1,Nbath
            write(unit_,"(A1)")" "
            hrep_aux=zero
            hrep_aux_nnn=bath_from_sym(dmft_bath%item(ibath)%lambda)
            Hrep_aux=nnn2lso_reshape(hrep_aux_nnn,Nlat,Nspin,Norb)
            write(unit_,string_fmt_first)dmft_bath%item(ibath)%v,"||  ",(DREAL(hrep_aux(1,jo)),jo=1,Nlat*Nspin*Norb),&        
                                                                 "|  ",(DIMAG(hrep_aux(1,jo)),jo=1,Nlat*Nspin*Norb)
            do io=2,Nlat*Nspin*Norb
               write(unit_,string_fmt) "  "  ,"||  ",(DREAL(hrep_aux(io,jo)),jo=1,Nlat*Nspin*Norb),&
                                              "|  ",(DIMAG(hrep_aux(io,jo)),jo=1,Nlat*Nspin*Norb)
            enddo
         enddo
         write(unit_,"(A1)")" "
      else
         write(LOGfile,"(A)")"Bath matrix too large to print: printing the parameters (including eventual offset)."
         write(unit_,"(A9,a5,90(A9,1X))")"V"," ","lambdas"        
         do ibath=1,Nbath
            write(unit_,"(F9.4,a5,90(F9.4,1X))")dmft_bath%item(ibath)%v,"|   ",&
                                                (dmft_bath%item(ibath)%lambda(io),io=1,dmft_bath%item(ibath)%N_dec)
         enddo
      endif
   else
      do ibath=1,Nbath
        !write number of lambdas
        write(unit,"(I3)")dmft_bath%item(ibath)%N_dec
      enddo
      do ibath=1,Nbath
        !write Vs
        write(unit,"(90(F21.12,1X))")dmft_bath%item(ibath)%v
        !write lambdas
         write(unit,*)(dmft_bath%item(ibath)%lambda(jo),jo=1,dmft_bath%item(ibath)%N_dec)
      enddo
   endif
   !
end subroutine write_dmft_bath





!+-------------------------------------------------------------------+
!PURPOSE  : save the bath to a given file using the write bath
! procedure and formatting: 
!+-------------------------------------------------------------------+
subroutine save_dmft_bath(file,used)
   character(len=*),optional :: file
   character(len=256)        :: file_
   logical,optional          :: used
   logical                   :: used_
   character(len=16)         :: extension
   integer                   :: unit_
   if(.not.dmft_bath%status)stop "save_dmft_bath error: bath is not allocated"
   used_=.false.;if(present(used))used_=used
   extension=".restart";if(used_)extension=".used"
   file_=str(str(Hfile)//str(ed_file_suffix)//str(extension))
   if(present(file))file_=str(file)
   unit_=free_unit()
   open(unit_,file=str(file_))
   call write_dmft_bath(unit_)
   close(unit_)
end subroutine save_dmft_bath




!+-------------------------------------------------------------------+
!PURPOSE  : copy the bath components back to a 1-dim array 
!+-------------------------------------------------------------------+
subroutine set_dmft_bath(bath_)
   real(8),dimension(:)                                  :: bath_
   integer                                               :: stride,ibath,Nmask,io,jo,isym
   logical                                               :: check
   !
   if(.not.dmft_bath%status)stop "get_dmft_bath error: bath not allocated"
   !
   check=check_bath_dimension(bath_)
   if(.not.check)stop "get_dmft_bath error: wrong bath dimensions"
   !
   do ibath=1,Nbath
      dmft_bath%item(ibath)%N_dec=0
      dmft_bath%item(ibath)%v=0d0
      dmft_bath%item(ibath)%lambda=0d0
   enddo
   !
   stride = 0
   do ibath=1,Nbath
      !Get N_dec
      stride = stride + 1
      dmft_bath%item(ibath)%N_dec=NINT(bath_(stride))
   enddo
   do ibath=1,Nbath
      !Get Vs
      stride = stride + 1
      dmft_bath%item(ibath)%v = bath_(stride)
      !get Lambdas
      dmft_bath%item(ibath)%lambda=bath_(stride+1:stride+dmft_bath%item(ibath)%N_dec)
      stride=stride+dmft_bath%item(ibath)%N_dec
   enddo
   !
end subroutine set_dmft_bath





!+-------------------------------------------------------------------+
!PURPOSE  : set the bath components from a given user provided 
! bath-array 
!+-------------------------------------------------------------------+
subroutine get_dmft_bath(bath_)
   real(8),dimension(:)   :: bath_
   integer                :: stride,ibath,Nmask,isym
   logical                :: check
   !
   if(.not.dmft_bath%status)stop "set_dmft_bath error: bath not allocated"
   !
   check = check_bath_dimension(bath_)
   if(.not.check)stop "set_dmft_bath error: wrong bath dimensions"
   !
   bath_=0.d0
   !
   stride = 0
   do ibath=1,Nbath
      !Get N_dec
      stride = stride + 1
      bath_(stride)=dmft_bath%item(ibath)%N_dec
   enddo
   do ibath=1,Nbath
      !Get Vs
      stride = stride + 1
      bath_(stride)=dmft_bath%item(ibath)%v
      !get Lambdas
      bath_(stride+1:stride+dmft_bath%item(ibath)%N_dec)=dmft_bath%item(ibath)%lambda      
      stride=stride+dmft_bath%item(ibath)%N_dec
   enddo
end subroutine get_dmft_bath


























