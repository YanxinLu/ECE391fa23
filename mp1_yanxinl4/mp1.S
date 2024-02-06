
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs
new_x:				.long 0x0
new_y:				.long 0x0
old_x:				.long 0x0
old_y:				.long 0x0
notifier:			.long 0x0

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
	# create the stack frame
	PUSHL %EBP
	MOVL  %ESP,%EBP
	PUSHL %EBX
	PUSHL %ESI
	PUSHL %EDI
	# call seperate functions
	CALL  update_missiles
	CALL  redraw_cities
	CALL  redraw_crosshairs
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
	# create the stack frame
	PUSHL %EBP
	MOVL  %ESP,%EBP
	PUSHL %EBX
	PUSHL %ESI
	PUSHL %EDI
	# link to input interface
	MOVL  12(%EBP), %EBX		# cmd
	# check the value of cmd
	CMPL  $0, %EBX
	JB    mp1_ioctl_other		# cmd < 0
	CMPL  $4, %EBX
	JA    mp1_ioctl_other		# cmd > 4
	JMP   *mp1_ioctl_jump_table(, %EBX, 4)	# jump_table + cmd*4
mp1_ioctl_other:
	MOVL  $-1, %EAX				# cmd = other, return -1
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret


# ----------------- Functions private to this file -------------------

# void update_missiles();
# Update all the missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
update_missiles:
	# create the stack frame
	PUSHL %EBP
	MOVL  %ESP,%EBP
	PUSHL %EBX
	PUSHL %ESI
	PUSHL %EDI
	MOVL $0, notifier
head_restart:
	# walk down the linked list
	MOVL mp1_missile_list, %EBX		# head of list pointer
	MOVL $0, %EDI					# set prev NULL if curr is head
	TESTL %EBX, %EBX
	JE update_done					# jump if head is null
update_loop:
	# store x,y
	MOVL X(%EBX), %ESI
	MOVL %ESI, old_x
	MOVL %ESI, new_x
	MOVL Y(%EBX), %ESI
	MOVL %ESI, old_y
	MOVL %ESI, new_y
	# check exploding
	MOVL EXPLODED(%EBX), %ESI
	CMPL $0, %ESI
	JNE update_missiles_explode		# jump if the missile is exploding
	# update X, Y
	MOVL old_x, %EDX
	ADDL VX(%EBX), %EDX				# update X
	MOVL %EDX, new_x				# store new X
	MOVL old_y, %EDX
	ADDL VY(%EBX), %EDX				# update Y
	MOVL %EDX, new_y				# store new Y
	# check move off
	MOVL new_x, %EDX
	CMPL $0, %EDX
	JL missile_remove			# X < 0
	CMPL $0x500000, %EDX
	JGE missile_remove			# X > 79
	MOVL new_y, %EDX
	CMPL $0, %EDX
	JL missile_remove			# Y < 0
	CMPL $0x190000, %EDX
	JGE missile_remove			# Y > 24
	# update new X, Y in the list
	MOVL new_x, %EDX
	MOVL %EDX, X(%EBX)
	MOVL new_y, %EDX
	MOVL %EDX, Y(%EBX)
	# check destination
	MOVL new_x, %EDX
	SARL $16, %EDX
	MOVL DEST_X(%EBX), %ECX			# dest_x
	CMPL %EDX, %ECX
	JE maybe_destination			# jump if x = dest_x
continue_moving:
	MOVL old_x, %EDX
	MOVL new_x, %ECX
	CMPL %EDX, %ECX
	JE maybe_notchange				# jump if x not change
change_missiles:
	PUSHL old_y						# erase before
	PUSHL old_x
	CALL cal_text_mode_location
	ADDL $8, %ESP
	MOVB $0x20, %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
redraw_missiles:
	PUSHL new_y						# draw new
	PUSHL new_x
	CALL cal_text_mode_location
	ADDL $8, %ESP
	MOVB C(%EBX), %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	# change pointers
	MOVL %EBX, %EDI					# prev
	MOVL NEXT(%EBX), %EBX			# next
	TESTL %EBX, %EBX
	JNE  update_loop				# jump if the next is not null
update_done:
	CMPL $0, notifier
	JNE notifying
notify_done:
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

notifying:
	CALL mp1_notify_user
	JMP notify_done

update_missiles_explode:
	CMPL $0, %EBX
	JE update_done
	PUSHL %EBX
	CALL missile_explode
	ADDL $4, %ESP
	# store return value
	ADDL %EAX, notifier
	MOVL EXPLODED(%EBX), %ESI
	DECL %ESI
	MOVL %ESI, EXPLODED(%EBX)
	CMPL $0, %ESI
	JE finish_exploding				# jump if EXPLODED = 0
	# erase before
	PUSHL old_y
	PUSHL old_x
	CALL cal_text_mode_location
	ADDL $8, %ESP
	MOVB $0x20, %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	# draw EXPLOSION
	PUSHL new_y
	PUSHL new_x
	CALL cal_text_mode_location
	ADDL $8, %ESP
	MOVB $EXPLOSION, %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	JMP explode_done
finish_exploding:
	PUSHL %EDI
	PUSHL %EBX
	CALL mp1_missile_remove
	ADDL $8, %ESP
explode_done:
	MOVL %EBX, %EDI					# prev
	CMPL $0, %EBX
	JE head_restart					# jump if the prev of deleted missile is null
	MOVL NEXT(%EBX), %EBX			# next
	TESTL %EBX, %EBX
	JNE  update_loop				# jump if the next is not null
	JMP  update_done

missile_remove:
	PUSHL %EDI
	PUSHL %EBX
	CALL mp1_missile_remove
	ADDL $8, %ESP
	MOVL %EBX, %EDI					# prev
	CMPL $0, %EBX
	JE  head_restart				# jump if the prev of deleted missile is null
	MOVL NEXT(%EBX), %EBX			# next
	TESTL %EBX, %EBX
	JNE  update_loop				# jump if the next is not null
	JMP  update_done

maybe_destination:
	MOVL new_y, %EDX
	SARL $16, %EDX
	MOVL DEST_Y(%EBX), %ECX
	CMPL %EDX, %ECX
	JE update_missiles_explode		# jump if reach destination
	JMP continue_moving				# jump if not reach destination

maybe_notchange:
	MOVL old_y, %EDX
	MOVL new_y, %ECX
	CMPL %EDX, %ECX
	JE redraw_missiles
	JMP change_missiles

# ----------------- Private Functions -------------------

# void redraw_cities();
# Redraw all the cities
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
redraw_cities:
	# create the stack frame
	PUSHL %EBP
	MOVL  %ESP,%EBP
	PUSHL %EBX
	PUSHL %ESI
	PUSHL %EDI
	# draw the three cities
	MOVL base_alive, %EBX
	MOVL $0x000000FF, %EDI
	MOVL $0, %EDX				# count cities
	MOVL $3876, %ECX			# 24*80*2+18*2
city_loop:
	MOVL $0, %ESI				# count num of bytes
	TESTL %EDI, %EBX
	JE draw_dead_loop
draw_loop:
	MOVL %ECX, %EAX
	PUSHL %ECX
	MOVB base_pic(,%ESI,1), %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	POPL %ECX
	INCL %ESI
	ADDL $2, %ECX
	CMPL $5, %ESI
	JB draw_loop
	ADDL $30, %ECX				# add to the next city
	# shift right one byte
	SHLL $8, %EDI
	INCL %EDX
	CMPL $3, %EDX
	JB city_loop
city_done:
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

draw_dead_loop:
	MOVL %ECX, %EAX
	PUSHL %ECX
	MOVB dead_base_pic(,%ESI,1), %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	POPL %ECX
	INCL %ESI
	ADDL $2, %ECX
	CMPL $5, %ESI
	JB draw_dead_loop
	ADDL $30, %ECX				# add to the next city
	SHLL $8, %EDI
	INCL %EDX
	CMPL $3, %EDX
	JB city_loop
	JMP city_done

# void redraw_crosshairs();
# Redraw all the crosshairs
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
redraw_crosshairs:
	# create the stack frame
	PUSHL %EBP
	MOVL  %ESP,%EBP
	PUSHL %EBX
	PUSHL %ESI
	PUSHL %EDI
	# redraw
	MOVL crosshairs_x, %EBX
	MOVL crosshairs_y, %ESI
	IMULL $2, %EBX, %EAX
	IMULL $160, %ESI, %ESI
	ADDL %ESI, %EAX
	MOVB $0x2B, %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

# int mp1_missile_remove(struct missile* curr, struct missile* prev)
# The function to erase missiles from the screen, removed from the linked list, and free it
# Inputs   : struct missile* curr - pointer to missile to be freed
#          : struct missile* prev - pointer to prev of the missile
# Outputs  : none
# Registers: no regitsers callee-saved
mp1_missile_remove:
	# create the stack frame
	PUSHL %EBP
	MOVL  %ESP, %EBP
	# link to input interface
	MOVL  8(%EBP), %EBX		# curr
	MOVL  12(%EBP), %EDI	# prev
	CMPL  $0, %EBX
	JE remove_done			# jump if curr is null
	# erase the missile
	PUSHL Y(%EBX)
	PUSHL X(%EBX)
	CALL cal_text_mode_location
	ADDL $8, %ESP
	MOVB $0x20, %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	# remove from the linked list
	MOVL NEXT(%EBX), %EDX
	CMPL $0, %EDI
	JE  remove_head
	MOVL %EDX, NEXT(%EDI)		# prev->next = curr->next
remove_free:
	# free the struct
	PUSHL %EBX
	CALL mp1_free
	ADDL $4, %ESP
	MOVL %EDI, %EBX					# curr = prev
remove_done:
	# tear down stack frame
	LEAVE
		ret

remove_head:
	MOVL %EDX, mp1_missile_list
	JMP remove_free

# int cal_text_mode_location(int x, int y)
# The function is used to calculate the index offset from the start of video memory
# Inputs   : int x
#		 	 int y
# Outputs  : offset
# Registers: Standard C calling convention
cal_text_mode_location:
	# create the stack frame
	PUSHL %EBP
	MOVL  %ESP, %EBP
	PUSHL %EBX
	PUSHL %ESI
	PUSHL %EDI
	# link to input interface
	MOVL  8(%EBP), %EBX		# x
	MOVL  12(%EBP), %ESI	# y
	# get the high 16 bit and calculate
	SARL  $16, %EBX				# shift right
	SARL  $16, %ESI
	IMULL $2, %EBX, %EAX
	IMULL $160, %ESI, %ESI
	ADDL %ESI, %EAX
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

# void mp1_ioctl_startgame();
# Initialize variables
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
mp1_ioctl_startgame:
	# initialize variables
	MOVL $0x00FFFFFF, base_alive
	MOVL $0, mp1_missile_list
	MOVL $0, mp1_score
	MOVL $40, crosshairs_x		# location of crosshair_x in the middle
	MOVL $12, crosshairs_y		# location of crosshair_y in the middle
	MOVL $0, new_x
	MOVL $0, new_y
	MOVL $0, old_x
	MOVL $0, old_y
	MOVL $0, notifier
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

# void mp1_ioctl_addmissile();
# Add a new missile from the user
# Inputs   : struct missile * user_missile
# Outputs  : 0 if success
# Registers: Standard C calling convention
mp1_ioctl_addmissile:
	# link to input interface
	MOVL  8(%EBP), %EBX		# user_missile pointer
	# allocate memory
	PUSHL $36
	CALL mp1_malloc
	ADDL $4, %ESP
	CMPL $0, %EAX			# pointer to new missile
	JE alloc_fail			# return null
	MOVL %EAX, %EDI
	# copy from user
	PUSHL $36				# n
	PUSHL %EBX				# from
	PUSHL %EDI				# to
	CALL mp1_copy_from_user
	ADDL $12, %ESP
	CMPL $0, %EAX
	JNE copy_fail
	MOVL mp1_missile_list, %EBX
	MOVL %EBX, NEXT(%EDI)	# new_missile -> next = head
	MOVL %EDI, mp1_missile_list			# head = new_missile
	MOVL $0, %EAX						# return value
addmissile_done:
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

copy_fail:
	PUSHL %EDI
	CALL mp1_free
	ADDL $4, %ESP
alloc_fail:
	MOVL $-1, %EAX
	JMP addmissile_done

# void mp1_ioctl_movexhairs();
# Movexhairs from the user
# Inputs   : unsigned long xhair_delta_packed
# Outputs  : always 0
# Registers: Standard C calling convention
mp1_ioctl_movexhairs:
	# link to input interface
	MOVL  8(%EBP), %EBX		# xhair_delta_packed
	# get x,y
	MOVSWL %BX, %EDI			# change_x
	SARL $16, %EBX				# change_y
	CMPL $0, %EDI
	JE maybe_samexhair
notsamexhair:
	# check range
	ADDL crosshairs_x, %EDI
	CMPL $80, %EDI
	JGE x_outrange_right		# crosshairs_x out of range
	CMPL $0, %EDI
	JL x_outrange_left			# crosshairs_x out of range
x_inrange:
	ADDL crosshairs_y, %EBX
	CMPL $25, %EBX
	JGE y_outrange_bottom		# crosshairs_y out of range
	CMPL $0, %EBX
	JL y_outrange_top
y_inrange:
	MOVL crosshairs_x, %EAX		# erase
	MOVL crosshairs_y, %ECX
	IMULL $2, %EAX, %EAX
	IMULL $160, %ECX, %ECX
	ADDL %ECX, %EAX
	MOVB $0x20, %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
	MOVL %EDI, crosshairs_x		# store
	MOVL %EBX, crosshairs_y
	IMULL $2, %EDI, %EAX		# redraw
	IMULL $160, %EBX, %EBX
	ADDL %EBX, %EAX
	MOVB $0x2B, %CL
	PUSHL %EDX
	CALL mp1_poke
	POPL %EDX
movexhair_done:
	MOVL $0, %EAX
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

x_outrange_right:
	MOVL $79, %EDI
	JMP x_inrange
y_outrange_bottom:
	MOVL $24, %EBX
	JMP y_inrange
x_outrange_left:
	MOVL $0, %EDI
	JMP x_inrange
y_outrange_top:
	MOVL $0, %EBX
	JMP y_inrange
maybe_samexhair:
	CMPL $0, %EBX
	JE movexhair_done
	JMP notsamexhair

# void mp1_ioctl_getstatus();
# Get the city status and score
# Inputs   : unsigned long* user_status
# Outputs  : 0 if success
# Registers: Standard C calling convention
mp1_ioctl_getstatus:
	# link to input interface
	MOVL 8(%EBP), %EBX		# user_status
	MOVL mp1_score, %ESI
	ANDL $0x0000FFFF, %ESI
	MOVL base_alive, %EDI
	ANDL $0x000000FF, %EDI
	JNE first_alive
first_c:
	MOVL base_alive, %EDI
	ANDL $0x0000FF00, %EDI
	JNE second_alive
second_c:
	MOVL base_alive, %EDI
	ANDL $0x00FF0000, %EDI
	JNE third_alive
third_c:
	# allocate memory
	PUSHL $4
	CALL mp1_malloc
	ADDL $4, %ESP
	CMPL $0, %EAX			# pointer to score
	JE allocf_fail			# return null
	MOVL %EAX, %EDI
	MOVL %ESI, (%EDI)
	# copy to user
	PUSHL $4				# n
	PUSHL %EDI				# from
	PUSHL %EBX				# to
	CALL mp1_copy_to_user
	ADDL $12, %ESP
	CMPL $0, %EAX
	JNE copyf_fail
	MOVL $0, %EAX						# return value
	# free the pointer
	PUSHL %EDI
	CALL mp1_free
	ADDL $4, %ESP
status_done:
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

copyf_fail:
	PUSHL %EDI
	CALL mp1_free
	ADDL $4, %ESP
allocf_fail:
	MOVL $-1, %EAX
	JMP status_done

first_alive:
	ORL $0x010000, %ESI
	JMP first_c
second_alive:
	ORL $0x020000, %ESI
	JMP second_c
third_alive:
	ORL $0x040000, %ESI
	JMP third_c

# void mp1_ioctl_endgame();
# End and free all
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
mp1_ioctl_endgame:
	MOVL mp1_missile_list, %EBX
	TESTL %EBX, %EBX
	JE free_done
free_loop:
	MOVL NEXT(%EBX), %EDI		# next
	PUSHL %EBX
	CALL mp1_free
	ADDL $4, %ESP
	# change pointers
	MOVL %EDI, %EBX
	TESTL %EBX, %EBX
	JNE  free_loop				# jump if the next is not null
free_done:
	# set nullptr
	MOVL $0, mp1_missile_list
	# return success
	# tear down stack frame
	POPL  %EDI
	POPL  %ESI
	POPL  %EBX
	LEAVE
		ret

mp1_ioctl_jump_table:
	.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

