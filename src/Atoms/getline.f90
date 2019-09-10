MODULE getline

  !Routine to read formatted input files
  use messages

  IMPLICIT NONE
  integer, parameter :: MAX_LENGTH=512 !maximum character read on a line
  integer, parameter :: MAX_KEYWORD_SIZE = 15

  CONTAINS

  
  SUBROUTINE getnextLine(unit, commentChar, FMT, line, Nread)

  !Read next line which is not a comment line nor an empty line
  !return that line and the len of the line Nread

  character(len=MAX_LENGTH), intent(out) :: line
  character(len=1), intent(in) :: commentChar
  integer, intent(out) :: Nread
  integer, intent(in) :: unit
  integer :: EOF
  character(len=*), intent(in) :: FMT

  Nread = 0
  EOF = 0

  !Is there problem here with an infiniy while ?
  do while (EOF == 0)
   read(unit, FMT, IOSTAT=EOF) line !'(512A)'
   Nread = len(trim(line))
   if ((line(1:1).eq.commentChar).or.(Nread==0)) cycle !comment or empty, go to next line
   ! line read exit ! to process it
   exit
  enddo ! if EOF > 0 reaches end of file, leaving
  
  RETURN
  END SUBROUTINE getnextLine

!! Keep this for retrocompatibility with old subroutine using this version
  SUBROUTINE getnextLine_old(unit, commentChar, FMT, line, Nread)

  !Read next line which is not a comment line nor an empty line
  !return that line and the len of the line Nread

  character(len=MAX_LENGTH), intent(out) :: line
  character(len=5) :: trline
  character(len=1), intent(in) :: commentChar
  integer, intent(out) :: Nread
  integer, intent(in) :: unit
  integer :: EOF, n, nMax, count
  character(len=*), intent(in) :: FMT

  Nread = 0
  n = 0
  EOF = 0
  nMax = 30 !if error stop at n = 15
  count = 0
  !write(*,*) "formatline used=", FMT
  do while (n.eq.0 .and. count.lt.nMax)
   read(unit, FMT, IOSTAT=EOF) line !'(512A)'
   !!write(*,*) n, "count=",count, line
   if (EOF.ne.0) then
    !write(*,*) "EOF error, skipping"
    !stop
   else if (len(trim(line)).eq.0) then
    !write(*,*) "Empty line, skipping"
    !stop
   else if (line(1:1).eq.commentChar) then
    !write(*,*) "Commented line, skipping"
    !stop
   else
    n = 1
    Nread = len(trim(line)) !len(line)
   end if
   count = count + 1
  end do

  if (n.eq.0) then
    write(*,*) "line=",line, count
    CALL error("Unable to read next line from file!")
  end if

  RETURN
  END SUBROUTINE getnextLine_old


  END MODULE getline
