# =============================================================================
# File:        drmario.asm
# Author:      Daniil Trukhin (daniilvtrukhin@gmail.com)
# Description: Main program and core routines for a Dr. Mario–style game.
# Version:     0.1
# Date:        2025-04-05
# License:     Copyright (c) 2025 Daniil Trukhin. All rights reserved.
#
# =============================================================================



######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       1
# - Unit height in pixels:      1
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################



    .data
    
        ##### Memory Mapped I/O #####
        PADDING:            .word 0:65536          # padding for display buffer
        ADDR_DSPL:          .word 0x10008000       # bitmap display base address
        ADDR_KBRD:          .word 0xffff0000       # keyboard base address

        ##### Play Area Boundaries #####
        .eqv PLAY_LEFT     4
        .eqv PLAY_RIGHT    18
        .eqv PLAY_NORTH    7
        .eqv PLAY_SOUTH    29

        ##### Colour Codes #####
        RED_CLR:            .word 0xff0000
        BLUE_CLR:           .word 0x0000ff
        YELLOW_CLR:         .word 0xffff00
        GREY_CLR:           .word 0x3f3f3f
        PURPLE_CLR:         .word 0x800080

        ##### Default Pill #####
        DEFAULT_PILL_X:         .word 11
        DEFAULT_PILL_Y:         .word 4
        DEFAULT_PILL_ORIENTATION: .word 0

        ##### Active Pill State #####
        PILL_X:             .word 11
        PILL_Y:             .word 4
        PILL_ORIENTATION:   .word 1
        PILL_COLOUR1:       .word 0x0
        PILL_COLOUR2:       .word 0x0

        ##### Timing and Game Speed #####
        FRAMES_UNTIL_NEXT_DIFFICULTY: .word 2000
        SPEED_UP_FACTOR:              .word 2
        TOTAL_ELAPSED_FRAMES:         .word 0
        CYCLE_COUNTER:                .word 0
        CYCLE_GRAVITY:                .word 40      # frames until pill moves
        CYCLE_GRAVITY_DEFAULT:        .word 40

        ##### Pill Array (History of Dropped Pills) #####
        PILL_ARR:           .space 10240            # storage for pill records
        CURR_OFFSET:        .word 0                 # next insertion offset
        ELEMENT_X:          .word 0
        ELEMENT_Y:          .word 0
        ELEMENT_ORIENTATION:.word 0
        ELEMENT_COLOUR1:    .word 0x0
        ELEMENT_COLOUR2:    .word 0x0

        ##### Virus Array #####
        VIRUS_ARR:          .word 0:300             # room for 100 viruses (x,y,color)
        VIRUS_OFFSET:       .word 0
        VIRUS_COUNT:        .word 3                 # initial number of viruses

        ##### Saved Pill #####
        PILL_SAVE:          .word 0                 # 0=no saved pill, 1=saved
        SAVE_PILL_X:        .word 24
        SAVE_PILL_Y:        .word 6
        SAVE_PILL_ORIENTATION: .word 1
        SAVE_PILL_COLOUR1:  .word 0x0
        SAVE_PILL_COLOUR2:  .word 0x0

        ##### Game State Flags #####
        START_SCREEN:       .word 1                 # 1=show start screen
        CURRENT_SCREEN:     .word 0
        VICTORY_STATE:      .word 0

    .text
    .globl main



###############################################################################
##### MAIN PROGRAM #####
###############################################################################



main:
    ##### Initialization #####

    # set the pill array offset to 0
    la $t0, CURR_OFFSET
    li $t1, 0
    sw $t1, 0($t0)

    # reset VICTORY_STATE
    la $t0, VICTORY_STATE
    li $t1, 0
    sw $t1, 0($t0)
    # reset START_SCREEN
    la $t0, START_SCREEN
    li $t1, 1
    sw $t1, 0($t0)

    # reset virus save
    lw $a0, VIRUS_COUNT
    jal create_virus_arr

    # reset pill save
    la $t0, PILL_SAVE
    li $t1, 0
    sw $t1, 0($t0)
    la $t0, SAVE_PILL_COLOUR1
    li $t1, 0x0
    sw $t1, 0($t0)
    la $t0, SAVE_PILL_COLOUR2
    sw $t1, 0($t0)

    # reset gravity difficulty
    la $t0, CYCLE_GRAVITY 
    lw $t1, CYCLE_GRAVITY_DEFAULT
    sw $t1, 0($t0)
    la $t0, CYCLE_COUNTER
    li $t1, 0
    sw $t1, 0($t0)
    la $t0, TOTAL_ELAPSED_FRAMES
    li $t1, 0
    sw $t1, 0($t0)

    jal clear_arr
    jal draw_main_screen
    jal generate_pill

    j game_loop

unpause:  # unpause the screen (redraw static parts)
    # reset START_SCREEN
    la $t0, START_SCREEN
    li $t1, 1
    sw $t1, 0($t0)
    jal draw_main_screen



###############################################################################
##### GAME LOOP #####
###############################################################################



game_loop:
    # process keyboard inputs
    jal keyboard_input

    # draw pill locations
    jal draw_main_screen
    jal draw_all_viruses
    jal draw_saved_pill
    jal draw_pills_from_arr
    jal draw_pill
    # update pill locations
    jal move_down_floating_pills

    jal gravity_pill
    jal draw_pill

    # sleep
    li $v0, 32  # sys call 32 = sleep
    li $a0, 8  # 8 ms
    syscall

    # increment CYCLE_COUNTER
    la $t0, CYCLE_COUNTER
    lw $t1, CYCLE_COUNTER
    addi $t1, $t1, 1
    sw $t1, 0($t0)

    j game_loop



###############################################################################
##### EXIT #####
###############################################################################



exit:
    li $v0, 10  # exit program
    syscall



###############################################################################
##### PROGRAM ROUTINES #####
###############################################################################



# -----------------------------------------------------------------------------
# (36) FUNCTION: draw_main_screen
# -----------------------------------------------------------------------------
# Description:
#   Draw the Dr. Mario main game screen and the Dr. Mario sprite. The Dr. Mario
#   sprite will be drawn with the correct number of coloured viruses based on
#   the state of 'VIRUS_ARR'.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_main_screen:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $t0, VIRUS_ARR  # $t0 = base/curr address in array 
    lw $t1, VIRUS_OFFSET
    add $t1, $t0, $t1  # $t1 = end address

    li $t2, 0  # $t2 = yellow virus found
    li $t3, 0  # $t3 = red virus found
    li $t4, 0  # $t4 = blue virus found

    lw $t5, YELLOW_CLR  # $t5 = yellow
    lw $t6, RED_CLR  # $t6 = red
    lw $t7, BLUE_CLR  # $t7 = blue

loop_36:
    beq $t0, $t1, end_loop_36

    lw $t8, 8($t0)
    beq $t8, $t5, yellow_36
    beq $t8, $t6, red_36
    beq $t8, $t7, blue_36

yellow_36:
    li $t2, 1
    j continue_36
red_36:
    li $t3, 2
    j continue_36
blue_36:
    li $t4, 4
continue_36:

    add $t0, $t0, 12  # increment curr address in array by 3 words
    j loop_36
end_loop_36:

    add $t8, $t2, $t3
    add $t8, $t4, $t8  # $t8 = sum of yrb code

    # play victory sound effect if all viruses are gone 
    lw $t9, VICTORY_STATE
    bne $t8, 0, not_victory
    bne $t9, 0, not_victory
    # modify victory state to 1
    la $t9, VICTORY_STATE
    li $t7, 1
    sw $t7, 0($t9)
    jal victory_sound_effect
not_victory:

    lw $t9, START_SCREEN
    beq $t9, 1, start_screen  # check if this is the start screen
    lw $t9, CURRENT_SCREEN  
    beq $t8, $t9, dont_redraw_screen_36
    j continue_2_36

start_screen:
    la $t9, START_SCREEN
    li $t7, 0
    sw $t7, 0($t9)  # set start screen to 0

continue_2_36:

    # check which y, r, b combination to draw
    bne $t8, 7, next_1_36
    jal draw_dr_mario_y_r_b
    j end_36
next_1_36:
    bne $t8, 3, next_2_36
    jal draw_dr_mario_y_r
    j end_36
next_2_36:
    bne $t8, 5, next_3_36
    jal draw_dr_mario_y_b
    j end_36
next_3_36:
    bne $t8, 1, next_4_36
    jal draw_dr_mario_y
    j end_36
next_4_36:
    bne $t8, 6, next_5_36
    jal draw_dr_mario_r_b
    j end_36
next_5_36:
    bne $t8, 2, next_6_36
    jal draw_dr_mario_r
    j end_36
next_6_36:
    bne $t8, 4, next_7_36
    jal draw_dr_mario_b
    j end_36
next_7_36:
    bne $t8, 0, next_8_36
    jal draw_dr_mario_e
next_8_36:

end_36:
    la $t0, CURRENT_SCREEN  # update the current screen
    sw $t8, CURRENT_SCREEN

    jal draw_bottle  # draw the bottle

dont_redraw_screen_36:

    # pop $ra after nested call
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (35) FUNCTION: remove_virus
# -----------------------------------------------------------------------------
# Description:
#   Removes a specified virus from 'VIRUS_ARR'.
#
# Arguments:
#   $a0 = x coordinate of virus to be removed.
#   $a1 = y coordinate of virus to be removed.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
remove_virus:
    move $t4, $a0  # $t4 = x coord
    move $t5, $a1  # $t5 = y coord

    la $t0, VIRUS_ARR  # $t0 = base/curr address in array
    lw $t1, VIRUS_OFFSET
    add $t1, $t0, $t1  # $t1 = end address

loop_35:
    beq $t0, $t1, end_loop_35

    lw $t2, 0($t0)  # $t2 = x coord
    lw $t3, 4($t0)  # $t3 = y coord
    # check if this is the virus to remove 
    bne $t2, $t4, virus_not_found
    bne $t3, $t5, virus_not_found
    j virus_found
virus_not_found:

    add $t0, $t0, 12  # increment curr address in array by 3 words
    j loop_35
end_loop_35:
    j end_35
virus_found:
    # decrement VIRUS_OFFSET
    lw $t2, VIRUS_OFFSET
    la $t3, VIRUS_OFFSET
    subi $t2, $t2, 12  # subtract 3 words from the current offset 
    sw $t2, 0($t3)  # the new VIRUS_OFFSET
    # remove the virus from the array
    la $t3, VIRUS_ARR
    add $t2, $t3, $t2  # $t2 = address of last element
    lw $t3, 0($t2)  # x coord of last element
    lw $t4, 4($t2)  # y coord of last element 
    lw $t5, 8($t2)  # colour of last element
    # store in the removal address 
    sw $t3, 0($t0)
    sw $t4, 4($t0)
    sw $t5, 8($t0)

end_35: 
    jr $ra



# -----------------------------------------------------------------------------
# (34) FUNCTION: draw_all_viruses
# -----------------------------------------------------------------------------
# Description:
#   Draws all viruses in 'VIRUS_ARR' to the game screen.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_all_viruses:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $t0, VIRUS_ARR  # $t0 = base/curr address in array
    lw $t1, VIRUS_OFFSET
    add $t1, $t0, $t1  # $t1 = end address

loop_34:
    beq $t0, $t1, end_loop_34

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    lw $a0, 0($t0)
    lw $a1, 4($t0)
    lw $a2, 8($t0)
    jal draw_pixel

    # revert temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    add $t0, $t0, 12  # increment curr address in array by 3 words
    j loop_34
end_loop_34:
    # pop $ra after nested call
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (33) FUNCTION: get_virus_from_array
# -----------------------------------------------------------------------------
# Description:
#   Gets the location of a virus with specified coordinates in 'VIRUS_ARR'.
#
# Arguments:
#   $a0 = x coordinate of virus to find.
#   $a1 = y coordinate of virus to find.
#
# Returns:
#   $v0 = offset where the virus is found or -1 if the virus couldn't be found.
#
# -----------------------------------------------------------------------------
get_virus_from_array:
    move $t0, $a0  # $t0 = x coord
    move $t1, $a1  # $t1 = y coord

    la $t2, VIRUS_ARR  # $t2 = base address
    lw $t3, VIRUS_OFFSET
    add $t3, $t2, $t3  # $t3 = end loop address

loop_33:
    beq $t2, $t3, end_loop_33

    # check if x and y coord are equal
    lw $t4, 0($t2)  # $t4 = x coord 
    lw $t5, 4($t2)  # $t5 = y coord 
    bne $t0, $t4, not_found_33
    bne $t1, $t5, not_found_33
    j found_33
not_found_33:

    addi $t2, $t2, 12  # increment the current address
    j loop_33
end_loop_33:
    # never found
    li $v0, -1
    j end_33
found_33:
    la $t6, VIRUS_ARR  # $t6 = base address of array
    sub $v0, $t2, $t6  # $v0 = offset
end_33:
    jr $ra



# -----------------------------------------------------------------------------
# (32) FUNCTION: create_virus_arr
# -----------------------------------------------------------------------------
# Description:
#   Spawn the virus array with viruses.
#
# Arguments:
#   $a0 = number of viruses to generate.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
create_virus_arr:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    la $t0, VIRUS_OFFSET
    li $t1, 0
    sw $t1, 0($t0)  # set the VIRUS_OFFSET to 0 

    move $t2, $a0  # $t2 = number of viruses
    li $t3, 0  # $t3 = virus count
    la $t5, VIRUS_ARR
    lw $t6, VIRUS_OFFSET
    add $t6, $t5, $t6  # $t6 = current virus address
loop_32:
    beq $t3, $t2, end_loop_32
restart_virus:
    li $v0 , 42  # get random number
    li $a0 , 0
    li $a1 , 15 # random range is [0, 14]
    syscall
    move $t0, $a0
    addi $t0, $t0, PLAY_LEFT  # $t0 = x coord

    li $v0 , 42  # get random number
    li $a0 , 0
    li $a1 , 17  # random range is [0, 17]
    syscall
    move $t1, $a0
    addi $t1, $t1, 13  # $t1 = y coord  # trimmed off the top to make sure it isn't too blocked

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t4, 0($sp)  # $t4
    addi $sp, $sp, -4
    sw $t5, 0($sp)  # $t5
    addi $sp, $sp, -4
    sw $t6, 0($sp)  # $t6


    # branch if these coord already exist in array
    move $a0, $t0
    move $a1, $t1
    jal get_virus_from_array

    # revert temporary registers
    lw $t6, 0($sp)  # $t6
    addi $sp, $sp, 4
    lw $t5, 0($sp)  # $t5
    addi $sp, $sp, 4
    lw $t4, 0($sp)  # $t4
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    beq $v0, -1, dont_restart_virus
    j restart_virus  # try to get new coordinates
dont_restart_virus:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t4, 0($sp)  # $t4
    addi $sp, $sp, -4
    sw $t5, 0($sp)  # $t5
    addi $sp, $sp, -4
    sw $t6, 0($sp)  # $t6

    jal colour_random

    # revert temporary registers
    lw $t6, 0($sp)  # $t6
    addi $sp, $sp, 4
    lw $t5, 0($sp)  # $t5
    addi $sp, $sp, 4
    lw $t4, 0($sp)  # $t4
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    move $t4, $v0  # $t4 = randomly selected colour

    # place the virus data in the array
    sw $t0, 0($t6)  # save x coord
    sw $t1, 4($t6)  # save y coord
    sw $t4, 8($t6)  # save randomly chosen colour

    # increment and update the virus offset 
    addi $t6, $t6, 12  # increment current virus address by 3 words
    sub $t7, $t6, $t5  # $t7 = Current Virus Address - Base Address = VIRUS_OFFSET
    la $t0, VIRUS_OFFSET 
    sw $t7, 0($t0)  # save the VIRUS_OFFSET

    addi $t3, $t3, 1  # increment virus count
    j loop_32
end_loop_32:
    # pop $ra after nested call
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (31) FUNCTION: game_over_pause
# -----------------------------------------------------------------------------
# Description:
#   Draws the game over screen and pauses the game until the user restarts the
#   game by pressing 'r' key.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
game_over_pause:
    lw $t0, ADDR_KBRD  # $t0 = base address for keyboard
    lw $t1, 0($t0)  # load first word from keyboard

    bne $t1, 1, game_over_pause
    lw $a0, 4($t0)  # load second word from keyboard

    bne $a0, 0x72, game_over_pause # check if the r key was pressed

    jr $ra  # return after r key is pressed



# -----------------------------------------------------------------------------
# (30) FUNCTION: draw_saved_pill
# -----------------------------------------------------------------------------
# Description:
#   Draws the saved pill at its designated location.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_saved_pill:
    lw $t0, SAVE_PILL_X  # x coord
    lw $t1, SAVE_PILL_Y # y coord
    lw $t2, SAVE_PILL_ORIENTATION  # orientation
    lw $t3, SAVE_PILL_COLOUR1  # colour1
    lw $t4, SAVE_PILL_COLOUR2  # colour2

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t4, 0($sp)  # $t4

    # draw first square of capsule
    move $a0, $t0  # x coord
    move $a1, $t1  # y coord
    move $a2, $t3  # colour1
    jal draw_pixel

    # revert temporary registers
    lw $t4, 0($sp)  # $t4
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

case_horizontal_30:
    li $t5, 1
    beq $t2, $t5, case_vertical_30
    addi $t0, $t0, 1  # increment x coord

    j end_30
case_vertical_30:
    addi $t1, $t1, 1  # increment y coord
end_30:
    # draw second square of capsule
    move $a0, $t0  # x coord
    move $a1, $t1  # y coord
    move $a2, $t4  # colour2
    jal draw_pixel

    # pop $ra after nested call
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (29) FUNCTION: clear_arr
# -----------------------------------------------------------------------------
# Description:
#   Resets 'PILL_ARR'.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
clear_arr:
    # set array offset to 0
    la $t0, CURR_OFFSET
    li $t1, 0
    sw $t1, 0($t0)

    jr $ra



# -----------------------------------------------------------------------------
# (28) FUNCTION: pause_game
# -----------------------------------------------------------------------------
# Description:
#   Draws the pause screen and pauses until the user enters the 'p' key.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
pause_game:
    lw $t0, ADDR_KBRD  # $t0 = base address for keyboard
    lw $t1, 0($t0)  # load first word from keyboard

    bne $t1, 1, pause_game
    lw $a0, 4($t0)  # load second word from keyboard

    bne $a0, 0x70, pause_game # check if the p key was pressed

    jr $ra  # return after p key is pressed



# -----------------------------------------------------------------------------
# (29) FUNCTION: draw_pills_from_arr
# -----------------------------------------------------------------------------
# Description:
#   Redraw all the pills in the pill array.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_pills_from_arr:
    la $t0, PILL_ARR  # $t0 = the current address in the array
    lw $t1, CURR_OFFSET
    add $t1, $t0, $t1  # $t1 = the address we stop the loop at

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

loop_29:
    beq $t0, $t1, loop_end_29  # end the loop if we have reached the last address of the array

    lw $t2, 8($t0)  # $t2 = orientation

horizontal_29:
    beq $t2, 3, orphan_29
    beq $t2, 1, vertical_29

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    # draw first coordinate
    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)  # $a1 = y coord 
    lw $a2, 12($t0)  # $a2 = colour1
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    # draw second coordinate
    lw $a0, 0($t0)  # $a0 = x coord 
    addi $a0, $a0, 1
    lw $a1, 4($t0)  # $a1 = y coord 
    lw $a2, 16($t0)  # $a2 = colour1
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    j end_29
vertical_29:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    # draw first coordinate
    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)  # $a1 = y coord 
    lw $a2, 12($t0)  # $a2 = colour1
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    # draw second coordinate
    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)  # $a1 = y coord 
    addi $a1, $a1, 1
    lw $a2, 16($t0)  # $a2 = colour1
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    j end_29
orphan_29:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    lw $a0, 0($t0)  # $a0 = x coord
    lw $a1, 4($t0)  # $a1 = y coord
    lw $a2, 12($t0)  # $a2 = colour1
    bne $a2, 0x0, not_black_29 
    lw $a2, 16($t0)  # $a2 = colour2
not_black_29:
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4
end_29:

    addi $t0, $t0, 20  # increment the current address in the array
    j loop_29
loop_end_29:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (27) FUNCTION: game_over_check
# -----------------------------------------------------------------------------
# Description:
#   Detects the game over condition. If game over occurs, the game over screen
#   is displayed.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
game_over_check:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $a0, 10
    li $a1, 6
    jal pixel_colour
    bne $v0, 0x0, this_is_game_over


    li $a0, 11
    li $a1, 6
    jal pixel_colour
    bne $v0, 0x0, this_is_game_over

    li $a0, 12
    li $a1, 6
    jal pixel_colour
    bne $v0, 0x0, this_is_game_over

    j continue_27

this_is_game_over:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jal game_over_sound_effect
    jal game_over_screen
    jal game_over_pause
    j main  # reset the game
continue_27:

    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (26) FUNCTION: move_down_floating_pills
# -----------------------------------------------------------------------------
# Description:
#   Redraw all pills in the array, while moving down floating pills.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
move_down_floating_pills:
    la $t0, PILL_ARR  # $t0 = the current address in the array
    lw $t1, CURR_OFFSET
    add $t1, $t0, $t1  # $t1 = the address we stop the loop at

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

pill_arr_loop_26:
    beq $t0, $t1, pill_arr_loop_end_26  # end the loop if we have reached the last address of the array

    lw $t5, 8($t0)  # $t5 = orientation
    beq $t5, 3, orphan_26  # skip to orphan processing section
    beq $t5, 1 vertical_26

    # check for collisions

    # horizontal
    # check left coordinate
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)

    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)
    addi $a1, $a1, 1  # $a1 = y coord + 1
    jal collision_check

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    beq $v0, 1, end_2_26

    # check right coordinate
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)

    lw $a0, 0($t0)
    addi $a0, $a0, 1  # $a0 = x coord + 1
    lw $a1, 4($t0)
    addi $a1, $a1, 1  # $a1 = y coord + 1
    jal collision_check

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    beq $v0, 1, end_2_26

    j no_collision_26
vertical_26:
    # check bottom coordinate ONLY
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)

    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)
    addi $a1, $a1, 2  # $a1 = y coord + 2
    jal collision_check

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    beq $v0, 1, end_2_26  # if there is a collision skip

no_collision_26:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)

    # erase the 1st pixel
    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)
    li $a2, 0x0  # $a2 = black
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    # erase the 2nd pixel           
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)

    # delete the original pixel
    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)
    # calculate second coordinate!
horizontal_2_26:
    lw $t5, 8($t0)  # $t5 = orientation
    beq $t5, 1, vertical_2_26

    addi $a0, $a0, 1

    j end_1_26
vertical_2_26:
    addi $a1, $a1, 1
end_1_26:
    li $a2, 0x0  # $a2 = black
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    # update the y coord in the array
    lw $t9, 4($t0)
    addi $t9, $t9, 1  # $t9 = new y coord
    sw $t9, 4($t0)  # update the y coord of the current pill in the array

    j end_2_26  # skip orphan section

orphan_26:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)

    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0) 
    addi $a1, $a1, 1  # $a1 = y coord + 1 (since we're lowering the pill)
    jal collision_check

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    beq $v0, 1, end_2_26  # don't move down this pill if there is a collision

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)

    # delete the original pixel
    lw $a0, 0($t0)  # $a0 = x coord 
    lw $a1, 4($t0)
    li $a2, 0x0  # $a2 = black
    jal draw_pixel

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    # update y coord
    lw $t9, 4($t0)
    addi $t9, $t9, 1  # $t9 = new y coord
    sw $t9, 4($t0)  # update the y coord of the current pill in the array
end_2_26:

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)
    addi $sp, $sp, -4
    sw $t1, 0($sp)        

    jal draw_pills_from_arr  # redraw pills so all positions are updated

    # pop temporary registers
    lw $t1, 0($sp)
    addi $sp, $sp, 4
    lw $t0, 0($sp)
    addi $sp, $sp, 4

    addi $t0, $t0, 20  # increment the current address in the array
    j pill_arr_loop_26
pill_arr_loop_end_26:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (22) FUNCTION: add_pill_arr
# -----------------------------------------------------------------------------
# Description:
#   Append a pill to the pill array from the pill data.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
add_pill_arr:
    # load the current pill data
    lw $t1, PILL_X
    lw $t2, PILL_Y
    lw $t3, PILL_ORIENTATION
    lw $t4, PILL_COLOUR1
    lw $t5, PILL_COLOUR2
    # store in the fallen pill arr
    la $t0, PILL_ARR
    lw $t6, CURR_OFFSET
    add $t0, $t0, $t6  # $t0 = address of current array index
    sw $t1, 0($t0)
    sw $t2, 4($t0)
    sw $t3, 8($t0)
    sw $t4, 12($t0)
    sw $t5, 16($t0)
    # increment the array offset 
    addi $t6, $t6, 20  # 20 byte offset (5 elements)
    la $t1, CURR_OFFSET
    sw $t6, 0($t1)

    jr $ra



# -----------------------------------------------------------------------------
# (24) FUNCTION: get_pill_from_arr
# -----------------------------------------------------------------------------
# Description:
#   Returns the offset location of a pill with given coordintes in the pill 
#   array. Additionally, pill data is loaded into element data in .data.
#
# Arguments:
#   $a0 = x coordinate of pill to be found.
#   $a1 = y coordinate of pill to be found.
#
# Returns:
#   $v0 = 0 if pill is found or 1 otherwise.
#   $v1 = The offset the pill was found at.
#
# -----------------------------------------------------------------------------
get_pill_from_arr:
    li $v0, 0  # assume success

    move $t3, $a0  # $t3 = x coord
    move $t4, $a1  # $t4 = y coord

    la $t0, PILL_ARR
    li $t1, 0  # $t1 = curr offset
    lw $t2, CURR_OFFSET  # final offset
pill_arr_loop24:
    beq $t1, $t2, pill_not_found24

    add $t5, $t0, $t1  # $t5 = current address of index
    lw $t6, 0($t5)  # $t6 = x coord
    lw $t7, 4($t5)  # $t7 = y coord

    # save the data in this address to .data
    la $t8, ELEMENT_X
    sw $t6, 0($t8)
    la $t8, ELEMENT_Y
    sw $t7, 0($t8)
    la $t8, ELEMENT_ORIENTATION
    lw $t9, 8($t5)
    sw $t9, 0($t8)
    la $t8, ELEMENT_COLOUR1
    lw $t9, 12($t5)
    sw $t9, 0($t8)
    la $t8, ELEMENT_COLOUR2
    lw $t9, 16($t5)
    sw $t9, 0($t8)

    bne $t6, $t3, continue24  # check if coords match
    beq $t7, $t4, pill_found24
continue24:

    # get second point of pill
    lw $t8, 8($t5)  # $t8 = orientation 
horizontal24:
    beq $t8, 1, vertical24

    addi $t6, $t6, 1  # increment x coord by 1

    j continue24_2
vertical24:
    addi $t7, $t7, 1  # increment y coord by 1
continue24_2:

    bne $t6, $t3, continue24_3  # check if coords match
    beq $t7, $t4, pill_found24
continue24_3:

    addi $t1, $t1, 20  # increment curr offset by 20 bytes 

    j pill_arr_loop24
pill_not_found24:
    li $v0, 1  # failure
pill_found24:
    move $v1, $t1
    jr $ra



# -----------------------------------------------------------------------------
# (23) FUNCTION: remove_pill_arr
# -----------------------------------------------------------------------------
# Description:
#   Removes a pill with given offset location from 'PILL_ARR'.
#
# Arguments:
#   $a0 = Offset location in 'PILL_ARR' of the pill to be removed.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
remove_pill_arr:
    move $t0, $a0  # $t0 = offset of the pill

    la $t3, PILL_ARR  # $t3 = address of pill array 
    add $t0, $t0, $t3  # $t0 = address of the pill in the array
    lw $t1, CURR_OFFSET  # $t1 = value of current offset
    la $t2, CURR_OFFSET  # $t2 = address of current offset

    # decrement CURR_OFFSET
    subi $t1, $t1, 20
    sw $t1, 0($t2)  # save decremented CURR_OFFSET

    # we need to save the last element at address $t0
    # grab last element data
    add $t1, $t1, $t3  # $t1 = address of last element
    lw $t4, 0($t1)  # $t4 = x coord last element
    lw $t5, 4($t1)  # $t5 = y coord last element
    lw $t6, 8($t1)  # $t6 = orientation last element
    lw $t7, 12($t1)  # $t7 = colour1
    lw $t8, 16($t1)  # $t8 = colour2
    # save last element data at address $t0 ($t0 = address of removed pill)
    sw $t4, 0($t0)
    sw $t5, 4($t0)
    sw $t6, 8($t0)
    sw $t7, 12($t0)
    sw $t8, 16($t0)

end23:
    jr $ra



# -----------------------------------------------------------------------------
# (20) FUNCTION: pixel_colour
# -----------------------------------------------------------------------------
# Description:
#   Returns the pixel colour at specified coordinates.
#
# Arguments:
#   $a0 = x coordinate of pixel.
#   $a1 = y coordinate of pixel.
#
# Returns:
#   $v0 = Colour of the pixel.
#
# -----------------------------------------------------------------------------
pixel_colour:
    move $t0, $a0  # $t0 = x coord 
    move $t1, $a1  # $t1 = y coord

    # scale by 8
    li $t9, 8
    mult $t0, $t9
    mflo $t0
    mult $t1, $t9
    mflo $t1

    # calculate offset
    li $t3, 256
    mult $t1, $t3
    mflo $t1
    add $t1, $t0, $t1  # $t1 = offset

    # convert offset to bytes
    li $t3, 4
    mult $t1, $t3
    mflo $t1  # $t1 = offset in bytes

    # add the offset to the display address
    lw $t0, ADDR_DSPL  # $t0 = base address for display
    add $t0, $t0, $t1  # $t0 = byte address in bitmap

    lw $t1, 0($t0)  # $t1 = colour
    move $v0, $t1

    jr $ra



# -----------------------------------------------------------------------------
# (19) FUNCTION: clear_col
# -----------------------------------------------------------------------------
# Description:
#   Clears columns with homogenous colours from the play area.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
clear_col:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $t0, PLAY_LEFT  # $t0 = start/curr x coord
x_loop19:
    li $t9, PLAY_RIGHT
    addi $t9, $t9, 1  # $t9 = end x coord
    beq $t0, $t9, x_end19

    li $t1, PLAY_NORTH  # $t1 = start/curr y coord 
    li $t2, 0x00  # set prev colour to black
    move $t3, $t1  # $t3 = chain start y index
y_loop19:            
    li $t9, PLAY_SOUTH
    addi $t9, $t9, 2  # $t9 = end y coord
    bge $t1, $t9, y_end19

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3

    # get curr colour
    move $a0, $t0
    move $a1, $t1
    jal pixel_colour
    move $t9, $v0  # $t9 = curr colour

    # pop temporary registers
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

colour_not_prev19:  # if the prev colour is not equal to curr
    beq $t2, $t9, continue19
    beq $t2, 0x0, reset_chain19  # skip if the previous colour was black

chain_gre_eq_four19:
    sub $t8, $t1, $t3  # $t8 = chain length

    blt $t8, 4, reset_chain19

    jal clear_row_col_sound_effect

del_loop19:  # delete the chain
    beq $t3, $t1, reset_chain19

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    # delete pixel
    move $a0, $t0
    move $a1, $t3
    li $a2, 0x0  # black
    jal draw_pixel

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    # get the pill to remove
    move $a0, $t0
    move $a1, $t3
    jal get_pill_from_arr
    move $t7, $v0  # $t7 = 0 if pill found, 1 otherwise
    move $t8, $v1  # $t8 = offset pill is found at in array

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # change colour1/colour2 to black in the array for this pill
pill_in_arr:
    beq $t7, 1, pill_not_in_arr  # test if the pill is in the array

    # if pill is already orphaned, delete it
    lw $t7, ELEMENT_ORIENTATION
is_orphan_19:
    bne $t7, 3, end_is_orphan_19  # if this isn't an orphan skip

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    move $a0, $t8  # load offset as argument
    jal remove_pill_arr

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    j continue_2_19  # skip the rest of this logic, we've already updated what we need
end_is_orphan_19:

    lw $t7, ELEMENT_X
    lw $t6, ELEMENT_Y

    # check if this is colour1 or colour2
case_colour1_19:
    bne $t0, $t7, case_colour2_19  # x coordinates not equal
    bne $t3, $t6, case_colour2_19  # y coordinates not equal

    # change colour1 to black
    li $t6, 0x0  # $t6 = black
    la $t7, PILL_ARR
    add $t7, $t7, $t8  # $t7 = address of the pill in the array
    sw $t6, 12($t7)

    lw $t6, ELEMENT_ORIENTATION
case_horizontal_19:
    beq $t6, 1, case_vertical_19

    lw $t6, ELEMENT_X
    addi $t6, $t6, 1  # $t6 = the updated x coord 
    sw $t6, 0($t7)  # update the x coord in the array

    j end_fi_19
case_vertical_19:
    lw $t6, ELEMENT_Y
    addi $t6, $t6, 1  # $t6 = the updated y coord 
    sw $t6, 4($t7)  # update the y coord in the array

    j end_fi_19
case_colour2_19:
    # change colour2 to black
    li $t6, 0x0  # $t6 = black
    la $t7, PILL_ARR
    add $t7, $t7, $t8  # $t7 = address of the pill in the array
    sw $t6, 16($t7)
    # we don't do anything to update the coordinate since we already have the correct coord
end_fi_19:
    # make this an orphaned pill
    la $t7, PILL_ARR
    add $t7, $t7, $t8  # $t7 = address of the pill in the array
    li $t6, 3  # $t6 = 3 => orphan orientation
    sw $t6, 8($t7)  # store the new orientation

    j continue_2_19

pill_not_in_arr:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    move $a0, $t0
    move $a1, $t3
    jal remove_virus 

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4
continue_2_19:

    addi $t3, $t3, 1  # increment chain index

    j del_loop19
reset_chain19:
    move $t3, $t1  # set chain start to curr
continue19:

    addi $t1, $t1, 1  # increment y coord
    move $t2, $t9  # set prev colour to curr colour

    j y_loop19
y_end19:
    addi $t0, $t0, 1

    j x_loop19
x_end19:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (18) FUNCTION: clear_row
# -----------------------------------------------------------------------------
# Description:
#   Clears rows with homogenous colours from the play area.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
clear_row:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $t1, PLAY_NORTH  # start/curr y coord
y_loop18:
    li $t9, PLAY_SOUTH
    addi $t9, $t9, 1  # $t9 = end y coord
    beq $t1, $t9, y_end18

    li $t0, PLAY_LEFT  # start/curr x coord 
    li $t2, 0x0  # set prev colour to black
    move $t3, $t0  # $t3 = chain start x index
x_loop18:            
    li $t9, PLAY_RIGHT
    addi $t9, $t9, 2  # $t9 = end x coord
    bge $t0, $t9, x_end18

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3

    # get curr colour
    move $a0, $t0
    move $a1, $t1
    jal pixel_colour
    move $t9, $v0  # $t9 = curr colour

    # pop temporary registers
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

colour_not_prev:  # if the prev colour is not equal to curr
    beq $t2, $t9, continue
    beq $t2, 0x0, reset_chain  # skip if the previous colour was black

chain_gre_eq_four:
    sub $t8, $t0, $t3  # $t8 = chain length
    blt $t8, 4, reset_chain

    jal clear_row_col_sound_effect

del_loop:  # delete the chain
    beq $t3, $t0, reset_chain

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    # delete pixel
    move $a0, $t3
    move $a1, $t1
    li $a2, 0x0  # black
    jal draw_pixel

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    # get the pill to remove
    move $a0, $t3
    move $a1, $t1
    jal get_pill_from_arr
    move $t7, $v0  # $t7 = 0 if pill found, 1 otherwise
    move $t8, $v1  # $t8 = offset pill is found at in array

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # change colour1/colour2 to black in the array for this pill
pill_in_arr_18:
    beq $t7, 1, pill_not_in_arr_18 # test if the pill is in the array

    # check if this is already orphaned, if it is, set both colours to black for deletion
    lw $t7, ELEMENT_ORIENTATION
is_orphan_18:
    bne $t7, 3, end_is_orphan_18  # if this isn't an orphan skip

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    move $a0, $t8  # load offset as argument
    jal remove_pill_arr

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    j continue_2_18  # skip the rest of this logic, we've already updated what we need
end_is_orphan_18:

    lw $t7, ELEMENT_X
    lw $t6, ELEMENT_Y

    # check if this is colour1 or colour2
case_colour1_18:  # if it is colour1, that means we want to keep colour2!
    bne $t3, $t7, case_colour2_18  # x coordinates not equal
    bne $t1, $t6, case_colour2_18  # y coordinates not equal

    # change colour1 to black
    li $t6, 0x0  # $t6 = black
    la $t7, PILL_ARR
    add $t7, $t7, $t8  # $t7 = address of the pill in the array
    sw $t6, 12($t7)

    lw $t6, ELEMENT_ORIENTATION
case_horizontal_18:
    beq $t6, 1, case_vertical_18

    lw $t6, ELEMENT_X
    addi $t6, $t6, 1  # $t6 = the updated x coord 
    sw $t6, 0($t7)  # update the x coord in the array

    j end_fi_2_18
case_vertical_18:
    lw $t6, ELEMENT_Y
    addi $t6, $t6, 1  # $t6 = the updated y coord 
    sw $t6, 4($t7)  # update the y coord in the array
end_fi_2_18:

    j end_fi_18
case_colour2_18:  # if it is colour2, that means we want to keep colour1!
    # change colour2 to black
    li $t6, 0x0  # $t6 = black
    la $t7, PILL_ARR
    add $t7, $t7, $t8  # $t7 = address of the pill in the array
    sw $t6, 16($t7)

    # we don't do anything to update the coordinate since we already have the correct coord
end_fi_18:
    # make this an orphaned pill
    la $t7, PILL_ARR
    add $t7, $t7, $t8  # $t7 = address of the pill in the array
    li $t6, 3  # $t6 = 3 => orphan orientation
    sw $t6, 8($t7)  # store the new orientation

    j continue_2_18

pill_not_in_arr_18:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t9, 0($sp)  # $t9

    move $a0, $t3
    move $a1, $t1
    jal remove_virus 

    # pop temporary registers
    lw $t9, 0($sp)  # $t9
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

continue_2_18:

    addi $t3, $t3, 1  # increment chain index

    j del_loop
reset_chain:
    move $t3, $t0  # set chain start to curr
continue:

    addi $t0, $t0, 1  # increment x coord
    move $t2, $t9  # set prev colour to curr colour

    j x_loop18
x_end18:
    addi $t1, $t1, 1

    j y_loop18
y_end18:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (16) FUNCTION: clear_screen
# -----------------------------------------------------------------------------
# Description:
#   Clears the screen to black pixels.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
clear_screen:
    li $t0, 0  # x coord
    li $t1, 0  # y coord
    li $t2, 32  # end index

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

y_loop:
    beq $t1, $t2, yloop_end
    li $t0, 0  # reset x coord
x_loop:
    beq $t0, $t2, xloop_end

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2

    # draw a black pixel 
    move $a0, $t0
    move $a1, $t1
    li $a2, 0x0
    jal draw_pixel

    # pop temporary registers
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    addi $t0, $t0, 1  # increment x coord
    j x_loop
xloop_end:
    addi $t1, $t1, 1  # increment y coord
    j y_loop
yloop_end:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (15) FUNCTION: collision_check
# -----------------------------------------------------------------------------
# Description:
#   Checks if there is a collision at a specified location.
#
# Arguments:
#   $a0 = x coordinate of pixel.
#   $a1 = y coordinate of pixel.
#
# Returns:
#   $v0 = 0 if no collision at the pixel or 1 otherwise.
#
# -----------------------------------------------------------------------------
collision_check:
    move $t0, $a0  # $t0 = x coord
    move $t1, $a1  # $t1 = y coord

    # scale by 8
    li $t9, 8
    mult $t0, $t9
    mflo $t0
    mult $t1, $t9
    mflo $t1

    # calculate offset
    li $t2, 256
    mult $t1, $t2
    mflo $t1
    add $t1, $t0, $t1  # $t1 = offset

    # convert offset to bytes
    li $t2, 4
    mult $t1, $t2
    mflo $t1  # $t1 = offset in bytes

    # add the offset to the display address
    lw $t0, ADDR_DSPL  # $t0 = base address for display
    add $t1, $t0, $t1  # $t1 = byte address in bitmap

    lw $t1, 0($t1)  # $t1 = current colour

case_no_collision:
    li $t0, 0x0  # $t0 = black
    bne $t1, $t0, case_collision

    li $t0, 0

    j end15_2
case_collision:
    li $t0, 1

end15_2:
    move $v0, $t0
    jr $ra



# -----------------------------------------------------------------------------
# (14) FUNCTION: gravity_pill
# -----------------------------------------------------------------------------
# Description:
#   Moves the active pill down after an elapsed amount of time. Resets 
#   'CYCLE_COUNTER' when specified number of cycles occurs.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
gravity_pill:
    lw $t0, CYCLE_COUNTER
    lw $t1, CYCLE_GRAVITY  # number of cycles for gravity to occur
    bge $t0, $t1, gravity
    j end14

gravity:
    # update TOTAL_ELAPSED_FRAMES
    lw $t2, TOTAL_ELAPSED_FRAMES
    la $t3, TOTAL_ELAPSED_FRAMES
    add $t2, $t2, $t0  # add CYCLE_COUNT to the TOTAL_ELAPSED_FRAME
    sw $t2, 0($t3)

    la $t2, CYCLE_COUNTER
    li $t3, 0
    sw $t3, 0($t2)

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    jal s_action

    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

increase_difficulty:
    lw $t2, TOTAL_ELAPSED_FRAMES
    lw $t3, FRAMES_UNTIL_NEXT_DIFFICULTY
    blt $t2, $t3, end14

    # reset TOTAL_ELAPSED_FRAMES
    li $t0, 0
    la $t1, TOTAL_ELAPSED_FRAMES
    sw $t0, 0($t1)

    lw $t0, CYCLE_GRAVITY  # divide by the speed up factor
    lw $t1, SPEED_UP_FACTOR
    div $t0, $t1
    mflo $t0
    la $t1, CYCLE_GRAVITY  # update CYCLE_GRAVITY with the smaller number
    sw $t0, 0($t1)

end14:
    jr $ra



# -----------------------------------------------------------------------------
# (10) FUNCTION: clear_pill
# -----------------------------------------------------------------------------
# Description:
#   Deletes the active pill from the screen.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
clear_pill:
    lw $t2, PILL_COLOUR1  # $t2 = PILL_COLOUR1
    la $t0, PILL_COLOUR1  # set colour to black
    li $t1, 0x0
    sw $t1, 0($t0)

    lw $t3, PILL_COLOUR2  # $t3 = PILL_COLOUR2
    la $t0, PILL_COLOUR2  # set colour to black
    li $t1, 0x0
    sw $t1, 0($t0)

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # save temporary registers
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3

    jal draw_pill  # draw over the original pill in black

    # pop temporary registers
    lw $t3, 0($sp)  # t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # t2
    addi $sp, $sp, 4

    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    # revert the original pill colours
    la $t0, PILL_COLOUR1
    sw $t2, 0($t0)

    la $t0, PILL_COLOUR2
    sw $t3, 0($t0)

    jr $ra



# -----------------------------------------------------------------------------
# (9) FUNCTION: generate_pill
# -----------------------------------------------------------------------------
# Description:
#   Generates default attributes for an active pill.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
generate_pill:
    la $t0, PILL_X
    lw $t1, DEFAULT_PILL_X
    sw $t1, 0($t0)

    la $t0, PILL_Y
    lw $t1, DEFAULT_PILL_Y
    sw $t1, 0($t0)

    la $t0, PILL_ORIENTATION
    lw $t1, DEFAULT_PILL_ORIENTATION
    sw $t1, 0($t0)

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    jal colour_random
    la $t0, PILL_COLOUR1
    move $t1, $v0
    sw $t1, 0($t0)

    jal colour_random
    la $t0, PILL_COLOUR2
    move $t1, $v0
    sw $t1, 0($t0)

    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (13) FUNCTION: s_action
# -----------------------------------------------------------------------------
# Description:
#   Moves the active pill down by 1 and starts a new pill if a collision 
#   occurs from the active pill.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
s_action:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, PILL_X
    lw $t1, PILL_Y
    lw $t2, PILL_ORIENTATION
    addi $t1, $t1, 1  # increment y coordinate locally

case_horizontal13:
    li $t3, 1
    beq $t2, $t3, case_vertical13

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    # check left point for collision
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # check branch
    li $t3, 1
    beq $t2, $t3, collision_occured

    # check right point for collision
    addi $t0, $t0, 1  # increment x coordinate
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, collision_occured

    j end13_1
case_vertical13:
    # only check bottom point for collision
    addi $t1, $t1, 1  # increment y again since this is the bottom point 
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, collision_occured  # collision occured

end13_1:
    jal clear_pill  # delete the current pill

    # increment y coordinate by 1
    la $t0, PILL_Y
    lw $t1, PILL_Y
    addi $t1, $t1, 1
    sw $t1, 0($t0)

    j end13_2

collision_occured:
    jal drop_sound_effect
    jal add_pill_arr  # add this pill to the prev pill arr
    jal generate_pill  # start new pill (resets previous pill)
    jal clear_row
    jal clear_col
    jal game_over_check

end13_2:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (12) FUNCTION: d_action
# -----------------------------------------------------------------------------
# Description:
#   Moves the active pill 1 coordinate to the right.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
d_action:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, PILL_X
    lw $t1, PILL_Y
    lw $t2, PILL_ORIENTATION
    addi $t0, $t0, 1  # increment x coordinate locally

case_horizontal12:
    li $t3, 1
    beq $t2, $t3, case_vertical12

    # only check right point for collision
    addi $t0, $t0, 1  # increment x again since this is the right point
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, end12_2  # collision occured

    j end12_1
case_vertical12:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    # check top point for collision
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # check branch
    li $t3, 1
    beq $t2, $t3, end12_2

    # check bottom point for collision
    addi $t1, $t1, 1  # increment y coordinate
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, end12_2  # collision occured

end12_1:
    jal clear_pill  # delete the current pill

    # increment x coordinate by 1
    la $t0, PILL_X
    lw $t1, PILL_X
    addi $t1, $t1, 1
    sw $t1, 0($t0)
end12_2:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (11) FUNCTION: a_action
# -----------------------------------------------------------------------------
# Description:
#   Moves the active pill 1 coordinate to the left.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
a_action:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, PILL_X
    lw $t1, PILL_Y
    lw $t2, PILL_ORIENTATION
    subi $t0, $t0, 1  # decrement x coordinate locally

case_horizontal11:
    li $t3, 1
    beq $t2, $t3, case_vertical11

    # only check left point for collision
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, end11_2  # collision occured

    j end11_1
case_vertical11:
    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    # check top point for collision
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision

    # pop temporary registers
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    # check branch
    li $t3, 1
    beq $t2, $t3, end11_2

    # check bottom point for collision
    addi $t1, $t1, 1  # increment y coordinate
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, end11_2  # collision occured

end11_1:
    jal clear_pill  # delete the current pill

    # decrement x coordinate by 1
    la $t0, PILL_X
    lw $t1, PILL_X
    subi $t1, $t1, 1
    sw $t1, 0($t0)  # update .data

end11_2:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (8) FUNCTION: w_action
# -----------------------------------------------------------------------------
# Description:
#   Switches the orientation of the active pill.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
w_action:
    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    lw $t0, PILL_X
    lw $t1, PILL_Y
    lw $t2, PILL_ORIENTATION

case_horizontal8:  # now becomes vertical
    li $t3, 1
    beq $t2, $t3, case_vertical8

    # only check bottom point for collision
    addi $t1, $t1, 1  # increment y
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, end8_2  # collision occured

    li $t1, 1  # $t1 = new orientation

    j end8_1
case_vertical8:  # now becomes horizontal
    # only check right point for collision
    addi $t0, $t0, 1  # increment x
    move $a0, $t0
    move $a1, $t1
    jal collision_check
    move $t2, $v0  # $t2 = 0 if no collision, 1 if there is a collision
    li $t3, 1
    beq $t2, $t3, end8_2  # collision occured

    li $t1, 0  # $t1 = new orientation

    # swap colours
    lw $t2, PILL_COLOUR1  # $t2 = PILL_COLOUR1
    lw $t3, PILL_COLOUR2  # $ $t3 = PILL_COLOUR2

    la $t4, PILL_COLOUR1  # $t4 = address of PILL_COLOUR1
    sw $t3, 0($t4)

    la $t4, PILL_COLOUR2  # $t4 = address of PILL_COLOUR2
    sw $t2, 0($t4)
end8_1:
    # save $t1 to the stack
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1

    li $v0, 31  # download sound
    li $a0, 100
    li $a1, 0
    li $a2, 114
    li $a3, 100
    syscall

    li $v0, 31
    li $a0, 100  # pitch
    li $a1, 500  # duration in ms
    li $a2, 114  # instrument
    li $a3, 100  # volume
    syscall

    jal clear_pill  # delete the current pill

    # pop $t1 from the stack
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4

    la $t0, PILL_ORIENTATION
    sw $t1, 0($t0)
end8_2:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (7) FUNCTION: keyboard_input
# -----------------------------------------------------------------------------
# Description:
#   Processes keyboard input during the game.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
keyboard_input:
    lw $t0, ADDR_KBRD  # $t0 = base address for keyboard
    lw $t1, 0($t0)  # load first word from keyboard

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

keyboard_event:
    bne $t1, 1, end7
    lw $a0, 4($t0)  # load second word from keyboard

    beq $a0, 0x71, exit  # check if the key q was pressed
    beq $a0, 0x72, main  # check if the key r was pressed
    beq $a0, 0x77, w  # check if the w key was pressed
    beq $a0, 0x61, a  # check if the a key was pressed
    beq $a0, 0x64, d  # check if the d key was pressed
    beq $a0, 0x73, s  # check if the s key was pressed
    beq $a0, 0x70, p  # check if the p key was pressed
    beq $a0, 0x7a, z
w:
    jal w_action
    j end7
a:
    jal a_action
    j end7
d:
    jal d_action
    j end7
s:
    jal s_action
    j end7
p:
    jal pause_screen
    jal pause_game
    j unpause  # unpause the game

z:  # save the current capsule to be used on a later turn
pill_stored:
    lw $t0, PILL_SAVE
    beq $t0, 0, pill_not_stored

    # black out the current pill in the playfield
    la $t1, PILL_COLOUR1
    li $t0, 0x0
    sw $t0, 0($t1)
    la $t1, PILL_COLOUR2
    sw $t0, 0($t1)
    jal draw_pill

    # Reset the coordinates
    la $t3, PILL_X 
    lw $t4, DEFAULT_PILL_X
    sw $t4, 0($t3)
    la $t3, PILL_Y
    lw $t4, DEFAULT_PILL_Y
    sw $t4, 0($t3)

    lw $t0, SAVE_PILL_ORIENTATION
    lw $t1, SAVE_PILL_COLOUR1
    lw $t2, SAVE_PILL_COLOUR2

    la $t3, PILL_ORIENTATION
    sw $t0, 0($t3)
    la $t3, PILL_COLOUR1
    sw $t1, 0($t3)
    la $t3, PILL_COLOUR2
    sw $t2, 0($t3)

    # black out the saved pill (since no pill is saved now)
    la $t0, SAVE_PILL_COLOUR1
    li $t1, 0x0
    sw $t1, 0($t0)
    la $t0, SAVE_PILL_COLOUR2
    sw $t1, 0($t0)
    jal draw_saved_pill

    # set pill saved back to 0
    la $t1, PILL_SAVE
    li $t0, 0
    sw $t0, 0($t1)

    j end7
pill_not_stored:
    lw $t0, PILL_ORIENTATION
    lw $t1, PILL_COLOUR1
    lw $t2, PILL_COLOUR2
    la $t3, SAVE_PILL_ORIENTATION
    sw $t0, 0($t3)
    la $t3, SAVE_PILL_COLOUR1
    sw $t1, 0($t3)
    la $t3, SAVE_PILL_COLOUR2
    sw $t2, 0($t3)

    # set PILL_SAVED to 1
    la $t1, PILL_SAVE
    li $t0, 1
    sw $t0, 0($t1)

    # black out the current pill in the playfield
    la $t1, PILL_COLOUR1
    li $t0, 0x0
    sw $t0, 0($t1)
    la $t1, PILL_COLOUR2
    sw $t0, 0($t1)
    jal draw_pill

    jal generate_pill  # start a new pill

    j end7

end7:
    # pop $ra
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (6) FUNCTION: colour_random
# -----------------------------------------------------------------------------
# Description:
#   Returns a random colour code (either red, blue, or yellow).
#
# Arguments:
#   None.
#
# Returns:
#   $v0 = Colour code.
#
# -----------------------------------------------------------------------------
colour_random:
    # generate random number
    li $v0, 42  # syscall 42 = random int
    li $a0, 0  # generator id
    li $a1, 3  # upper bound (exclusive)
    syscall
    move $t0, $a0  # $t0 = random colour code (0 = red, 1 = blue, 2 = yellow)

case_yellow:
    li $t1, 0
    beq $t0, $t1, case_red
    li $t1, 1
    beq $t0, $t1, case_blue

    lw $t0, YELLOW_CLR

    j end6
case_red:
    lw $t0, RED_CLR

    j end6
case_blue:
    lw $t0, BLUE_CLR
end6:
    move $v0, $t0

    jr $ra



# -----------------------------------------------------------------------------
# (5) FUNCTION: draw_pill
# -----------------------------------------------------------------------------
# Description:
#   Draws the pill from pill data in .data at its designated location.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_pill:
    lw $t0, PILL_X  # x coord
    lw $t1, PILL_Y # y coord
    lw $t2, PILL_ORIENTATION  # orientation
    lw $t3, PILL_COLOUR1  # colour1
    lw $t4, PILL_COLOUR2  # colour2

    # save $ra
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # save temporary registers
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    addi $sp, $sp, -4
    sw $t4, 0($sp)  # $t4

    # draw first square of capsule
    move $a0, $t0  # x coord
    move $a1, $t1  # y coord
    move $a2, $t3  # colour1
    jal draw_pixel

    # revert temporary registers
    lw $t4, 0($sp)  # $t4
    addi $sp, $sp, 4
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

case_horizontal:
    li $t5, 1
    beq $t2, $t5, case_vertical
    addi $t0, $t0, 1  # increment x coord

    j end5
case_vertical:
    addi $t1, $t1, 1  # increment y coord
end5:
    # draw second square of capsule
    move $a0, $t0  # x coord
    move $a1, $t1  # y coord
    move $a2, $t4  # colour2
    jal draw_pixel

    # pop $ra after nested call
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (4) FUNCTION: draw_bottle
# -----------------------------------------------------------------------------
# Description:
#   Draws the medicine bottle to the screen.
#
# Arguments:
#   None.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_bottle:
    # save $ra before nested calls
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # draw left vertical line of bottle
    li $a0, 3  # x coord
    li $a1, 6  # y coord
    lw $a2, GREY_CLR  # colour
    li $a3, 25  # line length
    jal draw_vertical

    # draw right vertical line of bottle
    li $a0, 19  # x coord
    li $a1, 6  # y coord
    lw $a2, GREY_CLR  # colour
    li $a3, 25  # line length
    jal draw_vertical

    # draw bottom horizontal line of bottle
    li $a0, 4  # x coord
    li $a1, 30  # y coord
    lw $a2, GREY_CLR  # colour
    li $a3, 15  # line length
    jal draw_horizontal

    # draw top-left horizontal line of bottle
    li $a0, 4  # x coord
    li $a1, 6  # y coord
    lw $a2, GREY_CLR  # colour
    li $a3, 6  # line length
    jal draw_horizontal

    # draw top-right horizontal line of bottle
    li $a0, 13  # x coord
    li $a1, 6  # y coord
    lw $a2, GREY_CLR  # colour
    li $a3, 6  # line length
    jal draw_horizontal

    # draw left vertical flask line of bottle
    li $a0, 9  # x coord
    li $a1, 4  # y coord
    lw $a2, GREY_CLR  # colour
    li $a3, 2  # line length
    jal draw_vertical

    # draw right vertical flask line of bottle
    li $a0, 13  # x coord
    li $a1, 4  # y coord
    lw $a2, GREY_CLR  # colour
    li $a3, 2  # line length
    jal draw_vertical

    # pop $ra after nested call
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    jr $ra



# -----------------------------------------------------------------------------
# (3) FUNCTION: draw_horizontal
# -----------------------------------------------------------------------------
# Description:
#   Draws a horizontal line at specified coordinates.
#
# Arguments:
#   $a0 = Starting x coordinate (0 <= x <= 31).
#   $a1 = Starting y coordinate (0 <= y <= 31).
#   $a2 = Length of the line.
#   $a3 = Colour of the line.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_horizontal:
    move $t0, $a0  # x coord
    move $t1, $a1  # y coord
    move $t2, $a2  # colour
    move $t3, $a3  # line length

    # find final y coord
    add $t3, $t0, $t3  # $t3 = final x coord

loop3:
    beq $t0, $t3, loop_end3

    # save temporary registers before draw_pixel call
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # t3
    # save $ra before draw_pixel call
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # draw pixel
    move $a0, $t0
    move $a1, $t1
    move $a2, $t2
    jal draw_pixel

    # revert $ra after draw_pixel call
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    # revert temporary registers after draw_pixel call
    lw $t3, 0($sp)  # t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # t0
    addi $sp, $sp, 4

    addi $t0, $t0, 1  # increment y coord

    j loop3
loop_end3:
    jr $ra



# -----------------------------------------------------------------------------
# (2) FUNCTION: draw_vertical
# -----------------------------------------------------------------------------
# Description:
#   Draws a vertical line at specified coordinates.
#
# Arguments:
#   $a0 = Starting x coordinate (0 <= x <= 31).
#   $a1 = Starting y coordinate (0 <= y <= 31).
#   $a2 = Length of the line.
#   $a3 = Colour of the line.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_vertical:
    move $t0, $a0  # x coord
    move $t1, $a1  # y coord
    move $t2, $a2  # colour
    move $t3, $a3  # line length

    # find final y coord
    add $t3, $t1, $t3  # $t3 = final y coord

loop2:
    beq $t1, $t3, loop_end2

    # save temporary registers before draw_pixel call
    addi $sp, $sp, -4
    sw $t0, 0($sp)  # $t0
    addi $sp, $sp, -4
    sw $t1, 0($sp)  # $t1
    addi $sp, $sp, -4
    sw $t2, 0($sp)  # $t2
    addi $sp, $sp, -4
    sw $t3, 0($sp)  # $t3
    # save $ra before draw_pixel call
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # draw pixel
    move $a0, $t0
    move $a1, $t1
    move $a2, $t2
    jal draw_pixel

    # revert $ra after draw_pixel call
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    # revert temporary registers after draw_pixel call
    lw $t3, 0($sp)  # $t3
    addi $sp, $sp, 4
    lw $t2, 0($sp)  # $t2
    addi $sp, $sp, 4
    lw $t1, 0($sp)  # $t1
    addi $sp, $sp, 4
    lw $t0, 0($sp)  # $t0
    addi $sp, $sp, 4

    addi $t1, $t1, 1  # increment y coord

    j loop2
loop_end2:
    jr $ra



# -----------------------------------------------------------------------------
# (1) FUNCTION: draw_pixel
# -----------------------------------------------------------------------------
# Description:
#   Draws a pixel to the screen.
#
# Arguments:
#   $a0 = x coordinate of pixel (0 <= x <= 31).
#   $a1 = y coordinate of pixel (0 <= y <= 31).
#   $a2 = Colour of the coordinate.
#
# Returns:
#   None.
#
# -----------------------------------------------------------------------------
draw_pixel:
    move $t0, $a0  # x coord
    move $t1, $a1  # y coord
    move $t2, $a2  # colour

    # scale x and y coord by 8 to account for new units (display settings)
    li $t3, 8
    mult $t0, $t3
    mflo $t0  # $t0 = x coord scaled by 8
    mult $t1, $t3
    mflo $t1  # $t1 = y coord scaled by 8

    li $t4, 0  # $t4 = loop2 index (increments by 1 until reaching 8)
outer_loop_1:
    beq $t4, 8, end_outer_loop_1

    li $t3, 0  # $t3 = loop1 index (increments by 1 until reaching 8)
inner_loop_1:
    beq $t3, 8, end_inner_loop_1

    add $t5, $t0, $t3  # computation x coord 
    add $t6, $t1, $t4  # computation y coord

    # calculate offset
    li $t9, 256  # originally 32
    mult $t6, $t9
    mflo $t6
    add $t5, $t5, $t6  # $t5 = offset

    # convert offset to byte address
    li $t9, 4
    mult $t5, $t9
    mflo $t5  # $t5 = offset byte address

    # add the offset to the display address
    lw $t9, ADDR_DSPL  # $t9 = base address for display

    add $t9, $t9, $t5  # $t9 = byte address in bitmap

    # paint the pixel
    sw $t2, 0($t9)

    addi $t3, $t3, 1

    j inner_loop_1
end_inner_loop_1:

    addi $t4, $t4, 1
    j outer_loop_1
end_outer_loop_1:

    jr $ra



###############################################################################
##### Image/Sprite Drawing files #####
###############################################################################



game_over_screen:
    .include "sprites/game_over_screen.asm"
    jr $ra

pause_screen:
    .include "sprites/pause_screen.asm"
    jr $ra

# yellow virus, red virus, blue virus
draw_dr_mario_y_r_b:
    .include "sprites/drmario_y_r_b.asm"
    jr $ra
# yellow virus, red virus
draw_dr_mario_y_r:
    .include "sprites/drmario_y_r.asm"
    jr $ra
# yellow virus, blue virus
draw_dr_mario_y_b:
    .include "sprites/drmario_y_b.asm"
    jr $ra
# yellow virus
draw_dr_mario_y:
    .include "sprites/drmario_y.asm"
    jr $ra
# red virus, blue virus
draw_dr_mario_r_b:
    .include "sprites/drmario_r_b.asm"
    jr $ra
# red virus
draw_dr_mario_r:
    .include "sprites/drmario_r.asm"
    jr $ra
# blue virus
draw_dr_mario_b:
    .include "sprites/drmario_b.asm"
    jr $ra
# no viruses
draw_dr_mario_e:
    .include "sprites/drmario_e.asm"
    jr $ra



###############################################################################
##### Sound Effects #####
###############################################################################



game_over_sound_effect:
    li $v0, 31  # Download sounds
    li $a0, 90
    li $a1, 0
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 31
    li $a0, 69  # pitch
    li $a1, 150  # duration in ms
    li $a2, 80  # instrument
    li $a3, 100    # volume
    syscall

    li $v0, 32  # sys call 32 = sleep
    li $a0, 100  # 100 ms
    syscall

    li $v0, 31
    li $a0, 71
    li $a1, 550
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 32  # sys call 32 = sleep
    li $a0, 500  # 500 ms
    syscall

    li $v0, 31
    li $a0, 60
    li $a1, 550
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 32  # sys call 32 = sleep
    li $a0, 450  # 500 ms
    syscall

    li $v0, 31
    li $a0, 63
    li $a1, 500
    li $a2, 80
    li $a3, 100
    syscall
    jr $ra

victory_sound_effect:
    li $v0, 31  # download sounds
    li $a0, 90
    li $a1, 0
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 31
    li $a0, 60  # pitch
    li $a1, 150  # duration in ms
    li $a2, 80  # instrument
    li $a3, 100    # volume
    syscall

    li $v0, 32  # sys call 32 = sleep
    li $a0, 200  # 100 ms
    syscall

    li $v0, 31
    li $a0, 72
    li $a1, 500
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 32  # sys call 32 = sleep
    li $a0, 200  # 500 ms
    syscall

    li $v0, 31
    li $a0, 76
    li $a1, 500
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 32  # sys call 32 = sleep
    li $a0, 200  # 500 ms
    syscall

    li $v0, 31
    li $a0, 79
    li $a1, 500
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 32  # sys call 32 = sleep
    li $a0, 200  # 500 ms
    syscall

    li $v0, 31
    li $a0, 84
    li $a1, 800
    li $a2, 80
    li $a3, 100
    syscall
    jr $ra

drop_sound_effect:
    li $v0, 31  # download
    li $a0, 69
    li $a1, 0
    li $a2, 80
    li $a3, 100
    syscall

    li $v0, 31
    li $a0, 69  # pitch
    li $a1, 150  # duration in ms
    li $a2, 80  # instrument
    li $a3, 50  # volume
    syscall
    jr $ra

clear_row_col_sound_effect:
    li $v0, 31  # Download midi
    li $a0, 60
    li $a1, 0
    li $a2, 70
    li $a3, 100
    syscall

    li $v0, 31  # clear row/col
    li $a0, 60  # pitch
    li $a1, 700  # duration in ms
    li $a2, 70  # instrument
    li $a3, 100  # volume
    syscall
    jr $ra
