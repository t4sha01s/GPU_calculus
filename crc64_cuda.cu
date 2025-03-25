#include <cuda.h>
#include "cuda_runtime.h"
#include <stdio.h>
#include <time.h>

#define BLOCK_SIZE 256
#define BLOCK_COUNT 216
 
#define CHAR_START 33
#define CHAR_END 123
#define CHAR2_START 48
#define CHAR2_END 112

typedef unsigned long long  crc_t;

// массив для хранения коэффициентов полинома
__constant__ crc_t crc_table[256];
static crc_t crc_table_cpu[256];

__constant__ char hex_digit[17] = "0123456789abcdef";
char hex_digit_cpu[17] = "0123456789abcdef";

// заполнение таблицы коэффициентов полинома
void gen_table(crc_t* tbl) {
	crc_t crc64Poly = 0xC96C5795D7870F42;
	for (unsigned i = 0; i < 256; ++i) {
		crc_t _crc = i;
		for (unsigned j = 0; j < 8; ++j) {
			_crc = _crc & 1 ? (_crc >> 1) ^ crc64Poly : _crc >> 1;
		}
		tbl[i] = _crc;
	}
}

// расчет crc64 на CPU
// параметры: crc - начальное значение, 
// data - строка, для которой выполняется расчет, 
// data_len - длина строки
crc_t crc_update_cpu(crc_t crc, const void* data, size_t data_len)
{
	const unsigned char* d = (const unsigned char*)data;
	unsigned int tbl_idx;

	while (data_len--) {
		tbl_idx = (crc ^ *d) & 0xff;
		crc = (crc_table_cpu[tbl_idx] ^ (crc >> 8));
		d++;
	}
	return crc;
}

// расчет crc64 на GPU
// параметры: crc - начальное значение, 
// data - строка, для которой выполняется расчет, 
// data_len - длина строки
__device__ inline crc_t crc_update_gpu(crc_t crc, const void* data, size_t data_len) {
	const unsigned char* d = (const unsigned char*)data;
	unsigned int tbl_idx;

	while (data_len--) {
		tbl_idx = (crc ^ *d) & 0xff;
		crc = (crc_table[tbl_idx] ^ (crc >> 8));
		d++;
	}
	return crc;
}


// поиск минимального crc64
// к строке добавляется три символа, сформированных из номера блока и номера нити
// и четыре символа, сформированных перебором в цикле
__global__ void kernel_CRC64_min(crc_t crc_pref, crc_t* seq, crc_t* res, crc_t* val) {
	unsigned tx = threadIdx.x;
	unsigned bx = blockIdx.x;
	crc_t tnum = blockIdx.x * BLOCK_SIZE + tx;

	__shared__ crc_t crc_table_k[256];
	__shared__ crc_t th_min[BLOCK_SIZE];
	__shared__ crc_t th_str[BLOCK_SIZE];

	// копирование таблицы коэффициентов полинома в разделяемую память
	if (tx == 0) {
		for (unsigned i = 0; i < 256; ++i) {
			crc_table_k[i] = crc_table[i];
		}
	}
	__syncthreads();

	// добавление трех символов, получаемых из номера блока и номера нити
	crc_t crc0 = crc_pref;
	crc_t ch3 = ((tnum >> 12) & 0x3f) + CHAR2_START;
	crc_t ch2 = ((tnum >> 6) & 0x3f) + CHAR2_START;
	crc_t ch1 = ((tnum) & 0x3f) + CHAR2_START;

	crc0 = crc_table_k[(crc0 ^ ch3) & 0xff] ^ (crc0 >> 8);
	crc0 = crc_table_k[(crc0 ^ ch2) & 0xff] ^ (crc0 >> 8);
	crc0 = crc_table_k[(crc0 ^ ch1) & 0xff] ^ (crc0 >> 8);

	crc_t crc_min = 0;
	crc_t str;
	th_min[tx] = 0;

	// добавление четырех символов из цикла перебора и поиск минимального значения
	for (crc_t i1 = CHAR_START; i1 < CHAR_END; ++i1) {
		crc_t cur_crc1 = (crc_table_k[(crc0 ^ i1) & 0xff] ^ (crc0 >> 8));
		for (crc_t i2 = CHAR_START; i2 < CHAR_END; ++i2) {
			crc_t cur_crc2 = (crc_table_k[(cur_crc1 ^ i2) & 0xff] ^ (cur_crc1 >> 8));
			for (crc_t i3 = CHAR_START; i3 < CHAR_END; ++i3) {
				crc_t cur_crc3 = (crc_table_k[(cur_crc2 ^ i3) & 0xff] ^ (cur_crc2 >> 8));
				for (crc_t i4 = CHAR_START; i4 < CHAR_END; ++i4) {
					crc_t cur_crc4 = (crc_table_k[(cur_crc3 ^ i4) & 0xff] ^ (cur_crc3 >> 8));
					if (cur_crc4 > th_min[tx]) {
						th_str[tx] = (ch3 << 48) | (ch2 << 40) | (ch1 << 32) | (i1 << 24) | (i2 << 16) | (i3 << 8) | (i4);
						th_min[tx] = cur_crc4;
					}
				}
			}
		}
	}

	__syncthreads();
	if (tx == 0) {
		crc_min = th_min[0];
		for (unsigned i = 0; i < BLOCK_SIZE; ++i) {
			if (th_min[i] >= crc_min) {
				crc_min = th_min[i];
				str = th_str[i];
			}
		}
		res[bx] = crc_min;
		seq[bx] = str;
	}

}

// функция для перевода в строку
void seq_to_str(crc_t seq, char* str) {
	for (unsigned i = 0; i < 7; ++i) {
		str[6 - i] = (char)((seq >> (i * 8)) & 0xff);
		str[7] = 0;
	}
}

// переписанная функция kernel_CRC64_min для CPU для сравнения времени работы 
void find_CRC64_min_CPU(crc_t crc_pref, crc_t* val, unsigned char* data) {
	data[0] = CHAR2_START;
	data[1] = CHAR2_START;
	data[7] = 0;
	crc_pref = (crc_table_cpu[(crc_pref ^ CHAR2_START) & 0xff] ^ (crc_pref >> 8));
	crc_pref = (crc_table_cpu[(crc_pref ^ CHAR2_START) & 0xff] ^ (crc_pref >> 8));
	crc_t crc_min = 0LL;
	for (crc_t i1 = CHAR2_START; i1 < CHAR2_END; ++i1) {
		crc_t cur_crc1 = (crc_table_cpu[(crc_pref ^ i1) & 0xff] ^ (crc_pref >> 8));
		for (crc_t i2 = CHAR_START; i2 < CHAR_END; ++i2) {
			crc_t cur_crc2 = (crc_table_cpu[(cur_crc1 ^ i2) & 0xff] ^ (cur_crc1 >> 8));
			for (crc_t i3 = CHAR_START; i3 < CHAR_END; ++i3) {
				crc_t cur_crc3 = (crc_table_cpu[(cur_crc2 ^ i3) & 0xff] ^ (cur_crc2 >> 8));
				for (crc_t i4 = CHAR_START; i4 < CHAR_END; ++i4) {
					crc_t cur_crc4 = (crc_table_cpu[(cur_crc3 ^ i4) & 0xff] ^ (cur_crc3 >> 8));
					for (crc_t i5 = CHAR_START; i5 < CHAR_END; ++i5) {
						crc_t cur_crc5 = (crc_table_cpu[(cur_crc4 ^ i5) & 0xff] ^ (cur_crc4 >> 8));
							if (cur_crc5 > crc_min) {
								crc_min = cur_crc5;
								data[2] = (uint8_t)i1;
								data[3] = (uint8_t)i2;
								data[4] = (uint8_t)i3;
								data[5] = (uint8_t)i4;
								data[6] = (uint8_t)i5;
								*val = ~cur_crc5;
							}
					}
				}
			}
		}
	}
}


// организация вычислений на GPU
void find_min_CRC64_GPU(crc_t crc_pref, crc_t* res, crc_t* seq) {
	const int size_d = 20;

	gen_table(crc_table_cpu);
	cudaMemcpyToSymbol(crc_table, &crc_table_cpu, 256 * sizeof(crc_t), 0, cudaMemcpyHostToDevice);

	crc_t d[size_d];
	crc_t cpu_seq[BLOCK_COUNT];
	crc_t cpu_res[BLOCK_COUNT];

	crc_t* dev_d = 0;
	crc_t* dev_seq = 0;
	crc_t* dev_res = 0;

	cudaMalloc((void**)&dev_d, size_d * sizeof(crc_t));
	cudaMalloc((void**)&dev_seq, BLOCK_COUNT * sizeof(crc_t));
	cudaMalloc((void**)&dev_res, BLOCK_COUNT * sizeof(crc_t));

	kernel_CRC64_min << < BLOCK_COUNT, BLOCK_SIZE >> > (crc_pref, dev_seq, dev_res, dev_d);

	cudaMemcpy(d, dev_d, size_d * sizeof(crc_t), cudaMemcpyDeviceToHost);
	cudaMemcpy(cpu_seq, dev_seq, BLOCK_COUNT * sizeof(crc_t), cudaMemcpyDeviceToHost);
	cudaMemcpy(cpu_res, dev_res, BLOCK_COUNT * sizeof(crc_t), cudaMemcpyDeviceToHost);

	crc_t res_min = cpu_res[0], seq_min = 0;
	for (unsigned i = 0; i < BLOCK_COUNT; ++i) {
		if (cpu_res[i] >= res_min) {
			res_min = cpu_res[i];
			seq_min = cpu_seq[i];
		}
	}

	*res = res_min;
	*seq = seq_min;

	cudaFree(dev_d);
	cudaFree(dev_seq);
	cudaFree(dev_res);
}


int main(int argc, char** argv) {

	// обработка аргументов командной строки
	if (argc < 2) {
		printf("err %d\n", argc);
		return 1;
	}

	// при вызове с аргументом check
	// возвращает слово count, количество работающих GPU
	if (strcmp(argv[1], "check") == 0) { 
		int deviceCount = 0;
		cudaGetDeviceCount(&deviceCount);
		printf("count %d", deviceCount);
	}
	// при вызове с аргументами calc и crc_pref,
	// где crc_pref - начальное значение crc64,
	// возвращает слово crc,
	// строку, которой соотвествует минимальное значение crc64,
	// минимальное значение crc64, 
	// суммарное количество итераций на всех нитях и блоках
	else if (strcmp(argv[1], "calc") == 0) {
		crc_t res, seq, count = 1;
		count = count * 90 * 90 * 90 * 90 * BLOCK_SIZE * BLOCK_COUNT;
		find_min_CRC64_GPU(~strtoull(argv[2], NULL, 10), &res, &seq);
		char str3[16];
		seq_to_str(seq, str3);
		printf("crc %s %016llx %lld", str3, ~res, count);
	}
	else {
		printf("err %d\n", argc);
	}

	return 0;
}