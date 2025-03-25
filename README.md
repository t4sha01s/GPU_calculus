Суть проекта:__
Для заданной строки поиск минимального (меньше заданного порога) значения crc64 путем перебора __
добавленных символов в конец строки__
Для расчетов используется алгоритм CRC-64/XZ__

client.py
Вызываемый файл. 
Формат вызова: client.py [string [number]]
string - строка, от которой начинает расчет (если не передается, присваивается "hello ")
number - число, меньше которого необходимо найти crc64 (если не передается, идет поиск 
минимального crc64)
Формат ответа:
1. строка, от которой выполнялся расчет + добавленные символы
2. найденная crc64 по постановке задачи
3. время выполнения
4. количество расчетных операций crc64 за единицу времени (млрд/с)

Пример вызова программы:
python3 client.py nothello
Результат выполнения:
Minimal crc64: nothello 9;[2/)Bz, 000000000000d5b8
Total time elapsed: 86.924 s, crc64 per second: 834.745 bln/s

flask1.py, crc64_cuda.cu
Файлы flask1.py, crc64_cuda.cu размещаются на каждой машине, которая будет использоваться для расчета
В файл flask1.py для каждой машины указывают актуальный ip-адрес
Файл crc64_cuda.cu компилируется командой nvcc -o crc64_cuda crc64_cuda.cu

Было выполнено сравнение скорости работы программы на CPU и GPU
1) Условия запуска: threads = 64, blocks = 1 

| # | млрд операций расчета crc64/с    |
 :---:   | :---: |
| CPU	(1 поток) | 0,494    |
| GPU (flask*) | 0,474    | 
| GPU (raw**) | 0,792    |

*flask - общее время расчета при вызове python3 client.py
**raw - ручной вызов программы на CUDA из командной строки 

Вывод: при слабой нагрузке использование GPU дает незначительный прирост (в 2 раза), а при 
использовании клиент-серверной архитектуры программа работает даже медленнее.

В отчете профилировщика была дана рекомендация выбора block_count кратным 108, дальнейшие 
эксперименты подтвердили данную рекомендацию
2) Тестирование параметров block_size и block_count
| block_size   | block_count	млрд операций расчета crc64/с    |
 :---:   | :---: |
| 256   | 128   | 218    |
| 256   | 108   | 255    |
| 256   | 216   | 369 (финальный вариант)    |
| 256   | 432   | 412    |

При запуске расчета на нескольких GPU скорость выполнения расчета растет пропорционально 
количеству GPU
| К-во GPU   | млрд операций расчета crc64/с    |
 :---:   | :---: |
| 1   | 369    |
| 2   | 738    |
