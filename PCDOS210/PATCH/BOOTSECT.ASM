TITLE - PC-DOS 2.1 - Patched Boot Sector ; Patch is labeled with "; ************ PATCH BEGIN ***************"

; Constants
BIOS_VIDEO_INT			EQU 10h
	SVC_PRINT_TTY			EQU 0Eh
BIOS_EQP_INT			EQU 11h
BIOS_DISK_INT			EQU 13h
	SVC_DISK_READ_SECTOR		EQU 02h
	SVC_READ_SECTOR_COUNT1		EQU (SVC_DISK_READ_SECTOR SHL 8h) OR 1h
BIOS_KEYBOARD_INT		EQU 16h
	SVC_READ_KEYBOARD	EQU 0h
BOOT_STRAP_LOADER		EQU 19h ; Int 19

INT_1E_OFFSET			EQU 1Eh * 4h
INT_1E_SEGMENT			EQU INT_1E_OFFSET + 2h

VOLUME_ID_LABEL_BYTES	EQU 20h
CONST_SECTOR_BYTES		EQU 200h

LENGTH_FILENAME_NAME	EQU 11

; Buffer address for reading the first Directory into
RAMDIRBUFFER SEGMENT AT 50h 
RAMDIRBUFFER ENDS

; Buffer address for reading IBMBIO/IBMDOS into
RAMBOOTSEG SEGMENT AT 70h
	IBMBIO_ENTRY LABEL FAR
RAMBOOTSEG ENDS

;; TODO, figure out how to get the ORG statement correct
	; For now, MASM generates all the 00's up to 7c00h when assembling
	; So those need to be stripped out externally

;; Start of Code, always loaded by BIOS at 7c00h
CODESEG SEGMENT
	assume CS:CODESEG, DS:CODESEG, SS:CODESEG
ORG 7C00h
ENTRY:
jmp MAIN													; Jump to MAIN function to start

SYSTEM_ID					db "IBM  2.0"					;LAST_FAT_SECTOR, Stored in SYSTEM_ID[0],[1], CHS_Cylinder stored in [5]
;; NOTE: The BIOS Parameter Block is device/drive specific
	; This one is from an SD-Cart Jr with CHS (1024/255/63) formatted in PC-DOS 2.10 with command: format c:/s
BIOS_PARAMETER_BLOCK:
BYTES_PER_SECTOR			dw 200h							; Number Bytes Per Sector
SECTORS_PER_CLUSTER			db 8h							; Number Sectors per cluster
RESERVED_SECTOR_CNT			dw 1h							; How many reserved sectors, just 1 (Boot sector)  
FAT_COPY_CNT				db 2h							; How many copies of the FAT
ROOT_DIR_ENTRIES			dw 200h							; Entries in the root directory table
DISK_SECTOR_CNT				dw 7D81h							; Total Disk Sectors ;LAST_DIR_SECTOR, Stored in DISK_SECTOR_CNT
FORMAT_ID					db 0F8h							; Fixed Disk
SECTORS_PER_FAT				dw 0Ch							; How many sectors does each FAT take up
SECTORS_PER_TRACK			dw 3Fh							; How many sectors are on each track
HEADS						dw 0FFh							; Heads (double sided)
SPECIAL_RESERVED_SECTOR_CNT	dw 1h							; Used by fixed disk for MBR

;; NOTE: The Disk/Head values are device/drive specific
	; This one is from an SD-Cart Jr with CHS (1024/255/63) formatted in PC-DOS 2.10 with command: format c:/s
DX_STORE:
DL_DISK						db 80h
DH_HEAD						db 0h

;; Note: DB_SEC_TO_READ is likely dependent on the version of DOS
	; This one is from an SD-Cart Jr with CHS (1024/255/63) formatted in PC-DOS 2.10 with command: format c:/s
DB_SEC_TO_READ				db 0Ah							; # Sectors to read for boot

;; NOTE: Disk Base Table is device/drive specific
	; This one is from an SD-Cart Jr with CHS (1024/255/63) formatted in PC-DOS 2.10 with command: format c:/s
DISK_BASE_TABLE:
STEP_RATE					db 0DFh
HEAD_LOAD					db 2h
WAIT_TIME					db 25h
DISK_BYTE_PER_SEC			db 2h ; 512 bytes
LAST_SEC					db 9h
GAP_LEN						db 2Ah
DATA_LEN					db 0FFh
GAP_LEN2					db 50h
DATA_VAL					db 0F6h
HEAD_SETTLE					db 0Fh
MOTOR_START					db 2h

BOOTSTRAP:													; "Restart the process" if non-sys disk
	int	BOOT_STRAP_LOADER

;; MAIN Function ---------------	
MAIN:
	cli														; Disable interrupts
	xor		ax,ax											; Set Stack Segment 
	mov		ss,ax											;   to 0000h
	mov		sp,offset ENTRY									; Stack pointer = 7c00h, grows downward
	mov		ds,ax											; DS=0000h, Interrupt vector table
	mov 	ds:word ptr INT_1E_SEGMENT,ax					; Set BIOS Diskette Parameter Table
	mov 	ds:word ptr INT_1E_OFFSET,offset DISK_BASE_TABLE;   to 0000:DISK_BASE_TABLE
	sti														; Re-enable interrupts
	int	BIOS_DISK_INT										; ax = 0000h, reset Diskette Drive
	jnc	DISK_RESET_SUCCESS									; Diskette Reset Succeeded, continue
	jmp DISK_RESET_ERROR									; Diskette Reset Failed, go to error routine
DISK_RESET_SUCCESS:											; Continue on!
	push	cs
	pop		ds												; Set DS=CS
CALCULATE_LAST_FAT_SECTOR:
	; LAST_FAT_SECTOR = [NUM_FATS * SECTORS/FAT] + Reserved_Special_SECTORS + RESERVED_SECTORS(BOOT)
	mov		al,FAT_COPY_CNT									; # FAT copies 
	cbw														; Convert to 16 bit
	mul		word ptr [SECTORS_PER_FAT]						; Multiply by SECTORS/FAT
	add		ax,word ptr [SPECIAL_RESERVED_SECTOR_CNT]		; Add Reserved Special SECTORS
	add		ax,word ptr [RESERVED_SECTOR_CNT]				; Add Reserved SECTORS
	mov		word ptr [SYSTEM_ID[0]],ax 						; LAST_FAT_SECTOR, store result in --- SYSTEM_ID[0][1] ---	
	mov		word ptr [DISK_SECTOR_CNT],ax 					; LAST_FAT_SECTOR, in here too but gets overridden DISK_SECTOR_CNT 
CALCULATE_NUM_DIR_SECTORS:
	; DIRECTORY_SECTORS = [[VOL_ID_LABEL_BYTES/ENTRY * ROOT_DIR_ENTRIES]+(BYTES/SECTOR-1)]/(BYTES/SECTOR)
	;   the BYTES/SECTOR - 1 is round up to the next SECTOR
	mov		ax,VOLUME_ID_LABEL_BYTES						; Volume ID label bytes
	mul		word ptr [ROOT_DIR_ENTRIES]						; Multiply by number of root directory entries
	add		ax,CONST_SECTOR_BYTES-1							; Round up to the next sector
	mov		bx,CONST_SECTOR_BYTES							; Load bytes per sector
	div		bx												; Divide Root directory bytes by bytes/sector, DIRECTORY_SECTORS
CALCULATE_LAST_DIR_SECTOR:
	; LAST_DIR_SECTOR = LAST_FAT_SECTOR + DIRECTORY_SECTORS
	add		word ptr [DISK_SECTOR_CNT],ax					; LAST_DIR_SECTOR, store result in --- DISK_SECTOR_CNT ---
CHECK_IF_BOOTDISK_LABEL:
	call	CHECK_IF_BOOTDISK								; Check if the disk is a functional boot disk
	jc		BOOTSTRAP										; If there was an error, restart this whole process from the beginning
															; User was told to replace the disk with a system disk
FOUND_BOOTDISK:												; If carry wasn't set, first two files were IBMBIO and IBMDOS, good boot
	mov		ax,word ptr [DISK_SECTOR_CNT]					; Load LAST_DIR_SECTOR (Boot sector + FAT copies + directories)
	mov		word ptr [LAST_DIR_SECTOR],ax					; Save LAST_DIR_SECTOR, store result in --- LAST_DIR_SECTOR ---
	mov		ax,RAMBOOTSEG 									; Set up ES/DS to point to the boot segment
	mov		es,ax
	mov		ds,ax
	mov		bx,0h											; Disk read buffer index to 0
LOAD_FILE_SECTORS:
; ************ PATCH BEGIN ***************
	mov		ax,cs:word ptr [DISK_SECTOR_CNT]				; Load NON_DATA_SECTORS
	call	CALCULATE_CHS_OFFSET							; Calculate CHS for first DATA sector
	mov		al,byte ptr CS:[DB_SEC_TO_READ] 				; Load how many sectors we want to read
	mov		ah,SVC_DISK_READ_SECTOR							; Setup disk read
	call	READ_SECTORS									; Read sectors
	jnc  	CHECK_FLOPPY									; If no carry, we finished getting all the wanted sectors
	nop														; NOPS to pad it out
	nop
	nop
	nop
	; Otherwise there was an error
	cmp		ah,04h 											; Good error, read part but not all of the sectors
	jne		DISK_RESET_ERROR								; If not error 04h, bail entirely
	sub		al,1 											; Error "sectors read" value is 1 > actually read
	sub		byte ptr CS:[DB_SEC_TO_READ],al 				; Subtract actually read sectors from desired read sectors
	xor 	ah,ah
	add		word ptr cs:[DISK_SECTOR_CNT],ax 				; Add actually read sectors to current offset
	mul		word ptr cs:[BYTES_PER_SECTOR]					; Calculate byte offset of read sectors
	add		bx,ax											; Add byte offset to buffer offset
	jmp		LOAD_FILE_SECTORS								; Load next group of sectors
; ************ PATCH END ***************
CHECK_FLOPPY:
	push	cs
	pop		ds												; DS = CS
	int		BIOS_EQP_INT									; Get BIOS equipment for system floppy disks															
	rol		al,1h											; Rotate AL twice to get installed floppy disk number as lower bits
	rol		al,1h					
	and		ax,3h											; Mask out the installed floppy disk number - 1
	jnz		CHECK_FIXED_DISK								; If multi-floppy drive system, we're done 
	inc		ax												; if Single floppy drive, increment by 1 for virtual drive
CHECK_FIXED_DISK:
	inc		ax												; EQP list was num-drives - 1, increment for actual number
	mov		cx,ax											; ---cx---: number of diskette drives
	test	byte ptr [DL_DISK],80h 							; Tests if boot device is a fixed fisk
	jnz		BOOT_DOS
	xor		ax,ax											
BOOT_DOS:													; AL = boot drive
	mov		bx,word ptr [LAST_DIR_SECTOR]					; Store LAST_DIR_SECTOR in BX
	jmp		IBMBIO_ENTRY ; DONE WITH BOOT LOADER!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
DISK_RESET_ERROR:
	mov		si,offset MSG_DISK_BOOT_FAIL					; Load Error Message address
	call	PRINT_ERROR										; Print Error Message
DISK_RESET_ERROR_HALT:										; Without working diskette drive,
	jmp		DISK_RESET_ERROR_HALT							;   Halt infinite loop
	
PRINT_ERROR:												; Error printing routine, SI = offset <message>
	lods	byte ptr cs:[si]								; Load char from error message into al, increment SI
	and		al,7fh											; Mask out high bit
	jz		SHARED_RETURN											; If '\0', done printing, return (technically, also if hex 80h)
	mov		ah,SVC_PRINT_TTY								; Prepare to print character
	mov		bx,07h											; BH=0 (Page=0), BL=7h (Color, Light Grey)
	int		BIOS_VIDEO_INT									; Print the character
	jmp		PRINT_ERROR										; Loop
	
CHECK_IF_BOOTDISK:
	mov		ax,RAMDIRBUFFER
	mov		es,ax											; Set up Disk Read buffer
	push	cs
	pop		ds												; DS = CS
	mov		ax,cs:word ptr [SYSTEM_ID[0]]					; Load LAST_FAT_SECTOR
	call	CALCULATE_CHS_OFFSET							; Calculate CHS of next sector after the LAST_FAT_SECTOR
	mov		bx,00h											; Disk Read Buffer offset from ES (RAMDIRKBUFFER:0000)
	mov		ax,SVC_READ_SECTOR_COUNT1						; Set AH = 2, AL = 1 (read 1 sector), prep for disk read
	call	READ_SECTORS									; Call READ_SECTORS function to read in the first directory table
	jc		NON_SYS_DISK_OR_DISK_ERR						; If error reading the sector, go to error routine
	xor		di,di											; Zero index
	mov		cx,LENGTH_FILENAME_NAME							; Set CX to 11????
SET_LOWER_CASE: 											; For first two records in RAM, force to lower case for comparison
	or		byte ptr es:[di],20h							; Set bit 6 of character in first name record, doesn't affect <space>
	or		byte ptr es:[di+20h],20h						; Set bit 6 of character in second name record, doesn't affect <space>
	inc		di												; increment index
	loop	SET_LOWER_CASE									; Loop to set all of them
CHECK_FILE_NAMES:
	xor		di,di											; Reset index to point to first record
	mov		si,offset IBMBIO_FILENAME						; Set source index  to beginning of the filename
	mov		cx,LENGTH_FILENAME_NAME							; Set counter to length of file name
	cld														; Clear direction flag aka set to increment
	repe	cmpsb ; es:di,si								; Compare es:di,ds:si, repeat until counter is 0
	jnz		NON_SYS_DISK_OR_DISK_ERR						; If not 0, first file name doesn't match, throw error and set carry flag
	mov		di,20h											; Set index to second record
	mov		si,offset IBMDOS_FILENAME						; Set source index to second file
	mov		cx,LENGTH_FILENAME_NAME							; Set counter to length of file name
	repe	cmpsb											; Compare es:di,ds:si, repeate until counter is 0
	jnz		NON_SYS_DISK_OR_DISK_ERR						; If not 0, first file name doesn't match, throw error and set carry flag
SHARED_RETURN:														; Shared return
	ret
	
NON_SYS_DISK_OR_DISK_ERR:
	mov		si,offset MSG_NON_SYS_DISK						; Load offset for Non System Disk or Disk error
	call	PRINT_ERROR										; Print error message to screen
	mov		ah,SVC_READ_KEYBOARD							; Setup keyboard read
	int		BIOS_KEYBOARD_INT								; Wait for keystroke
	stc														; Set carry flag to indicate error
	ret
	
CALCULATE_CHS_OFFSET: 
; Input: AX, Desired Absolute Sector - 1 (sector before the one we want)
; Output: CHS coordinates
; This function says "I want the Sector after AX, calculate which head it's on and what setor relative to the head
	push	ds
	push	cs
	pop		ds								; Set DS = CS
	xor		dx,dx							; DX = 0h for division (otherwise whatever garvage there could trigger unintentional overflow error)
	div		word ptr [SECTORS_PER_TRACK]	; LAST_FAT_SECTOR/# SECTORS_PER_TRACK=Tracks-0[AX] Whole tracks sectors, Remainder sectors [DX]
	inc		dl								; CHS_RELATIVE_SECTOR_OFFSET = Remainder Sectors + 1, 
											;Inc remaining sectors by 1 since sector counts start at 1						
	mov		byte ptr [FORMAT_ID],dl			; CHS_RELATIVE_SECTOR_OFFSET, in --- FORMAT_ID ---
	xor		dx,dx							; DX = 0h for next division
	div		word ptr [HEADS]				; CHS_HEAD = Whole Tracks / # Heads
	mov		byte ptr [DH_HEAD],dl			; CHS_HEAD, in --- [DH_HEAD] ---
	mov		word ptr [SYSTEM_ID[5]],ax		; CHS_Cylinder = remainder of the heads division, in --- [SYSTEM_ID[5]] ---
	pop		ds
	ret
	
READ_SECTORS:
; Int 13 CHS values:
; AH = Service, AL = # Sectors to read
; CH = Cylinder (7-0), CL = Cylinder(9-8) Sector (5-0)
; DH = Head, DL = Drive
; ES:BX = Buffer address pointer
	mov		dx,word ptr cs:[SYSTEM_ID[5]]	; Retrieve CHS Cylinder value into DX
	mov		cl,6h							; Prep for left shift
	shl		dh,cl							; Shift upper bits of the cylinder left 6 (see int13 CH value)
	or		dh,byte ptr cs:[FORMAT_ID]		; OR in the Relative Sector offset (lower 5 bits)
	mov		cx,dx							; move byte reversed Cylinder/Sector calculation to CX
	xchg	ch,cl							; Get them in the correct order
	mov		dx,word ptr cs:[DX_STORE]		; Set the Head/Drive number
	int		BIOS_DISK_INT					; Read AL sectors into ES:BX
	ret
	
LAST_DIR_SECTOR				dw 0h
MSG_NON_SYS_DISK			db 0Dh,0Ah,"Non-System disk or disk error",0Dh,0Ah
MSG_NON_SYS_DISK_2			db "Replace and strike any key when ready",0Dh,0Ah,00h
MSG_DISK_BOOT_FAIL			db 0Dh,0Ah,"Disk Boot failure",0Dh,0Ah,00h
IBMBIO_FILENAME				db "ibmbio  com0"
IBMDOS_FILENAME				db "ibmdos  com0"

ORG (ENTRY + CONST_SECTOR_BYTES - 2)
SIGNATURE					dw 0AA55h
CODESEG ENDS
END
