#include <stdio.h>
#include <string.h>
#include <stdlib.h>

unsigned char *padded_boot_sector; /* Buffer to hold ROM data */

/* Main Function */
int main(argc, argv, envp)
	int argc;
	char **argv;
	char **envp;
{
	/* VARIABLES */
	int i; /* Loop counter */
	char c; /* Read char buffer */
	
	char *input_file_name; 
	FILE *input_file; 
	unsigned int input_file_size; /* binary size of input file */
	char *output_input_file_name; 
	FILE *output_file;
	
	/* CODE */
	fprintf(stderr,"Remove Padding from assembled Boot Sector\n");
	if ( argc != 3 ){
		fprintf(stderr,"Arg $1: Input - Padded Boot Sector Binary File Name\n");
		fprintf(stderr,"Arg $2: Output - Raw Boot Sector Binary File Name\n");
		return 1;
	}
	
	input_file_name = argv[1];
	fprintf(stderr,"Input - Padded Boot Sector Binary: %s\n",input_file_name);
	output_input_file_name = argv[2];
	fprintf(stderr,"Output - Raw Boot Sector Binary: %s\n",output_input_file_name);
	
	/* Open input file, read as binary */
	input_file = fopen(input_file_name,"rb");
	
	/* Determine Padded Boot Sector size */
	input_file_size=0;
	while(1){
		fgetc(input_file); /* Read character */
		if(feof(input_file)){ /* Check if end of file */
			break;
		}
		input_file_size++; 
	}
	rewind(input_file);
	
	/* Error out if file is zero */
	if ( input_file_size == 0 ){
		fprintf(stderr,"Error reading file, got 0 byte size, exiting.\n");
		fclose(input_file);
		return 2;
	}
	else {
		fprintf(stderr,"Padded Boot Sector Binary Size: %d bytes.\n",input_file_size);
	}
	
	/* Allocate memory and read the file */
	padded_boot_sector = (unsigned char*)malloc(input_file_size); /* Allocate memory buffer for the input_file bytes */
	for (i = 0; i < input_file_size; i++){
		c = fgetc(input_file); 
		padded_boot_sector[i] = c;
	}
	fclose(input_file);
	
	/* Output last 512 bytes */
	output_file = fopen(output_input_file_name,"wb");
	for ( i = input_file_size - 512; i < input_file_size; i++ ){
		fprintf(output_file,"%c",padded_boot_sector[i]);
	}
	fclose(output_file);

	free(padded_boot_sector); /* Free the memory buffer */

	return 0;
}
/* Comment out "^Z" in Linux for gcc, uncomment in DOS for IBMC Compiler */

