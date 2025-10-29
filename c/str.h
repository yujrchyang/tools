#ifndef STR_H
#define STR_H

#include <stdio.h>
#include <ctype.h>
#include <string.h>

/*
 * returns exponent (2^x=n) in range KiB..EiB (2^10..2^60)
 */
static int str_get_exp(unsigned long long n)
{
	int shift;

	for (shift = 10; shift <= 60; shift += 10) {
		if (n < (1ULL << shift))
			break;
	}
	return shift - 10;
}

inline void str_byte_to_human(unsigned long long size, char *buf, size_t buf_size)
{
	int exp, dec;
	unsigned long long frac;
	char c;
	char *letters = "BKMGTPE";

	exp = str_get_exp(size);
	c = *(letters + (exp ? exp / 10 : 0));
	dec  = exp ? size / (1ULL << exp) : size;
	frac = exp ? size % (1ULL << exp) : 0;
	frac = frac / (1ULL << (exp - 10));
	while (frac >= 100) {
		frac /= 10;
	}

	if (frac)
		snprintf(buf, buf_size, "%d.%llu%c", dec, frac, c);
	else
		snprintf(buf, buf_size, "%d%c", dec, c);
}


#endif // STR_H
