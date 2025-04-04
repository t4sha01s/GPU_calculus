Суть проекта: <br />
Для заданной строки поиск минимального (меньше заданного порога) значения crc64 путем перебора <br />
добавленных символов в конец строки. <br />
Для расчетов используется алгоритм CRC-64/XZ <br />
 <br />
client.py <br />
Основной файл.  <br />
Формат вызова: client.py [string [number]] <br />
string - строка, от которой начинает расчет (если не передается, присваивается "hello ") <br />
number - число, меньше которого необходимо найти crc64 (если не передается, идет поиск  <br />
минимального crc64) <br />
Формат ответа: <br />
1. Строка, от которой выполнялся расчет + добавленные символы. <br />
2. Найденная crc64 по постановке задачи. <br />
3. Время выполнения. <br />
4. Количество расчетных операций crc64 за единицу времени (млрд/с). <br />
 <br />
Пример вызова программы: <br />
python3 client.py nothello <br />
Результат выполнения: <br />
Minimal crc64: nothello 9;[2/)Bz, 000000000000d5b8 <br />
Total time elapsed: 86.924 s, crc64 per second: 834.745 bln/s <br />
 <br />
flask1.py, crc64_cuda.cu <br />
Файлы flask1.py, crc64_cuda.cu размещаются на каждой машине, которая будет использоваться для расчета. <br />
В файле flask1.py для каждой машины указывается актуальный ip-адрес. <br />
Файл crc64_cuda.cu компилируется командой nvcc -o crc64_cuda crc64_cuda.cu <br />
 <br />
Было выполнено сравнение скорости работы программы на CPU и GPU. <br />
1) Условия запуска: threads = 64, blocks = 1  <br />

| # | млрд операций расчета crc64/с    |
| :---:   | :---: | 
| CPU	(1 поток) | 0,494    |
| GPU (flask*) | 0,474    | 
| GPU (raw**) | 0,792    |

*flask - общее время расчета при вызове python3 client.py <br />
**raw - ручной вызов программы на CUDA из командной строки  <br />
 <br />
Вывод: при слабой нагрузке использование GPU дает незначительный прирост (в 2 раза), а при  <br />
использовании клиент-серверной архитектуры программа работает даже медленнее. <br />
 <br />
В отчете профилировщика была дана рекомендация выбора block_count кратным 108, дальнейшие  <br />
эксперименты подтвердили данную рекомендацию. <br />
2) Тестирование параметров block_size и block_count
| block_size   | block_count   | млрд операций расчета crc64/с    |
 :---:   | :---: | :---: |
| 256   | 128   | 218    |
| 256   | 108   | 255    |
| 256   | 216   | 369    |
| 256   | 432   | 412    |

При запуске расчета на нескольких GPU скорость выполнения расчета растет пропорционально  <br />
количеству GPU. 
| К-во GPU   | млрд операций расчета crc64/с    |
 :---:   | :---: |
| 1   | 369    |
| 2   | 738    |
