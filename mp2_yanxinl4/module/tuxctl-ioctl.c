/* tuxctl-ioctl.c
 *
 * Driver (skeleton) for the mp2 tuxcontrollers for ECE391 at UIUC.
 *
 * Mark Murphy 2006
 * Andrew Ofisher 2007
 * Steve Lumetta 12-13 Sep 2009
 * Puskar Naha 2013
 */

#include <asm/current.h>
#include <asm/uaccess.h>

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/file.h>
#include <linux/miscdevice.h>
#include <linux/kdev_t.h>
#include <linux/tty.h>
#include <linux/spinlock.h>

#include "tuxctl-ld.h"
#include "tuxctl-ioctl.h"
#include "mtcp.h"

#define debug(str, ...) \
	printk(KERN_DEBUG "%s: " str, __FUNCTION__, ## __VA_ARGS__)

static unsigned long leds;
unsigned long buttons;
unsigned int ack = 1;



/************************ Helper function for ioctl *************************/

/* 
 * tuxctl_ioctl_init
 *   DESCRIPTION: Initialize variables associated with the driver. 
 *   INPUTS: tty - state associated with a tty while open
 *   OUTPUTS: none
 *   RETURN VALUE: return 0
 *   SIDE EFFECTS: none
 */
int 
tuxctl_ioctl_init(struct tty_struct* tty){
	unsigned char opcode_buf[2];
	/* Enable Button interrupt-on-change. */
	opcode_buf[0] = MTCP_BIOC_ON;
	/* Put the LED display into user-mode. */
	opcode_buf[1] = MTCP_LED_USR;
	/* Check ack */
	// while(ack == 0);
	ack = 0;
	//printk("tuxctl_ioctl_init\n");
	/* Write bytes out to the tty. */
	tuxctl_ldisc_put(tty, opcode_buf, 2);
	buttons = 0xFF;
	leds = 0;
	// ack = 0;
	return 0;
}


/* 
 * tuxctl_ioctl_buttons
 *   DESCRIPTION: Set the low byte of the arg to be the pressed button
 *   INPUTS: arg - pointer to a 32-bit integer
 *   OUTPUTS: none
 *   RETURN VALUE: return -EINVAL error if the pointer is not valid, otherwise 0
 *   SIDE EFFECTS: change arg
 */
int
tuxctl_ioctl_buttons(unsigned long* arg){
	//printk("tuxctl_ioctl_buttons\n");
	if(!arg) return -EINVAL;
	*arg = buttons;
	return 0;
}


/* 
 * tuxctl_ioctl_setLED
 *   DESCRIPTION: setLED based on the arg
 *   INPUTS: tty - state associated with a tty while open
 * 			 arg - the low 16 bits are hex value to be displayed on the 7 segment displays
 * 				   the 27:24 bits are the LED should be turned on
 *                 the 31:28 bits are the decimal points
 *   OUTPUTS: none
 *   RETURN VALUE: return 0
 *   SIDE EFFECTS: change arg
 */
int 
tuxctl_ioctl_setLED(struct tty_struct* tty, unsigned long arg){
	unsigned seg, led, dem;
	// Mapping from 7-segment to bits
 	// The 7-segment display is:
	// 	  _A
	// 	F| |B
	// 	  -G
	// 	E| |C
	// 	  -D .dp
 	// The map from bits to segments is:       eg.
 	// __7___6___5___4____3___2___1___0__         | B
 	// | A | E | F | dp | G | C | B | D |         
 	// +---+---+---+----+---+---+---+---+         | C   ->  0x06  -> 1
	/* Set the hex mask from 0 to F */
	unsigned char hex_bitmask[16] = {0xE7, 0x06, 0xCB, 0x8F, 0x2E, 0xAD, 0xED, 0x86,
								     0xEF, 0xAF, 0xEE, 0x6D, 0xE1, 0x4F, 0xE9, 0xE8};  /* bit is 1 if the line is used as above */
	// Arguments: >= 1 bytes
	// 	byte 0 - Bitmask of which LED's to set:
	// 	__7___6___5___4____3______2______1______0___
 	// 	| X | X | X | X | LED3 | LED2 | LED1 | LED0 | 
 	// 	----+---+---+---+------+------+------+------+
	/* Set LED buffer */
	unsigned char led_buf[6] = {MTCP_LED_SET, 0xF, 0, 0, 0, 0};
	int i;
	/* Check ack */
	if(ack==0) return 0;
	ack = 0;
	/* Load arguments */
	seg = arg & 0xFFFF;			/* 15:0 bits */
	led = (arg & 0xF0000) >> 16;		/* 19:16 bits */
	dem = (arg & 0xF000000) >> 24;		/* 27:24 bits */
	/* Set bitmask */
	for(i = 0; i < 4; i++){
		if((led & (1 << i))){
			led_buf[i + 2] = hex_bitmask[(seg >> 4*i) & 0xF];
			if(dem & (1 << i)){
				led_buf[i + 2] |= 0x10;				/* add demical point */
			}
		}
	}
	/* Save LEDs */
	leds = arg;
	// while(ack == 0);
	// ack = 0;
	/* write bytes */
	tuxctl_ldisc_put(tty, led_buf, 6);
	// ack = 0;
	return 0;
}




/************************ Protocol Implementation *************************/

/* tuxctl_handle_packet()
 * IMPORTANT : Read the header for tuxctl_ldisc_data_callback() in 
 * tuxctl-ld.c. It calls this function, so all warnings there apply 
 * here as well.
 */
void tuxctl_handle_packet (struct tty_struct* tty, unsigned char* packet)
{
    unsigned a, b, c;
	unsigned char opcode_buf[2];
    a = packet[0]; /* Avoid printk() sign extending the 8-bit */
    b = packet[1]; /* values when printing them. */
    c = packet[2];
	// printk("tuxctl_handle_packet\n");
    /*printk("packet : %x %x %x\n", a, b, c); */

	switch (a)
	{
		case MTCP_ACK:
			ack = 1;
			break;
		case MTCP_BIOC_EVENT: 
			// byte 1  __7_____4___3___2___1_____0____
			// 	| 1 X X X | C | B | A | START |
			// 	-------------------------------
			// byte 2  __7_____4_____3______2______1_____0___
			// 	| 1 X X X | right | down | left | up |
			// 	--------------------------------------
			// buttons
			// | right | left | down | up | c | b | a | start |
			buttons = (b & 0xF) | ((c & 0x9) << 4) | ((c & 0x2) << 5) | ((c & 0x4) << 3);
			break;
		case MTCP_RESET:
			/* Check ack */
			// while(ack == 0);
			// ack = 0;
			/* Enable Button interrupt-on-change. */
			opcode_buf[0] = MTCP_BIOC_ON;
			/* Put the LED display into user-mode. */
			opcode_buf[1] = MTCP_LED_USR;
			/* Write bytes out to the tty. */
			tuxctl_ldisc_put(tty, opcode_buf, 2);
			tuxctl_ioctl_setLED(tty, leds);
			//ack = 0;
			break;
		default: break;
	}
}

/******** IMPORTANT NOTE: READ THIS BEFORE IMPLEMENTING THE IOCTLS ************
 *                                                                            *
 * The ioctls should not spend any time waiting for responses to the commands *
 * they send to the controller. The data is sent over the serial line at      *
 * 9600 BAUD. At this rate, a byte takes approximately 1 millisecond to       *
 * transmit; this means that there will be about 9 milliseconds between       *
 * the time you request that the low-level serial driver send the             *
 * 6-byte SET_LEDS packet and the time the 3-byte ACK packet finishes         *
 * arriving. This is far too long a time for a system call to take. The       *
 * ioctls should return immediately with success if their parameters are      *
 * valid.                                                                     *
 *                                                                            *
 ******************************************************************************/

/* 
 * tuxctl_ioctl
 *   DESCRIPTION: call functions by cmd
 *   INPUTS: tty - state associated with a tty while open
 * 			 cmd - func cmd
 * 			 arg - func args
 *   OUTPUTS: none
 *   RETURN VALUE: return 0
 *   SIDE EFFECTS: change arg
 */
int 
tuxctl_ioctl (struct tty_struct* tty, struct file* file, 
	      unsigned cmd, unsigned long arg)
{
	//printk("tuxctl_ioctl\n");
    switch (cmd) {
		case TUX_INIT: return tuxctl_ioctl_init(tty);
		case TUX_BUTTONS: return tuxctl_ioctl_buttons((unsigned long*)arg);
		case TUX_SET_LED: return tuxctl_ioctl_setLED(tty, arg);
		case TUX_LED_ACK: return 0;
		case TUX_LED_REQUEST: return 0;
		case TUX_READ_LED: return 0;
		default:
			return -EINVAL;
    }
}
