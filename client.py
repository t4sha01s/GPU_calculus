from threading import Thread, Lock
from queue import Queue
import time
import sys
from subprocess import run, Popen, PIPE
from requests import get
from fastcrc import crc64

# список url-адресов, на которых запускается flask
urls = ["http://127.0.0.1:5101", "http://192.168.100.3:5101"]
# количество итераций для расчета crc (соответсвует первому добавленному символу к исходной строке)
# от 1 до 64
steps_count = 8

lock = Lock()
end_work = False

# функция, отвечающая за расчет crc64 и общение с flask 
# выполняется для каждого потока
def calculation_crc64(url_address):
    while True:
        # если присутствует флаг окончания работы (end_work = True), завершаем рабоут функции
        lock.acquire()
        end_fl = end_work
        lock.release()
        if end_fl is True:
            break
        # если очередь не пуста, обрабатываем следующий блок расчета crc64
        if not q_inp.empty():
            ipar = q_inp.get()
            # передает предпросчитанную crc64 
            response = get(url_address+"/calc64", params = {"crc_pref" : str(ipar[0])})
            # распаковка ответа
            q_out.put([chr(ipar[1]), response.content, url_address])
        # иначе ожидаем появления сообщений в очереди
        else:
            time.sleep(0.1)


if __name__ == '__main__':  

    # оработка параметров командной строки
    number_to_compare = None
    input_text = 'hello '
    if len(sys.argv) == 1:
        print("String not specified, using default string '" + input_text + "'")
        print("Target number to compare not specified, finding the minimal one")
    elif len(sys.argv) > 3:
        raise Exception("Incorrect number of arguments")
    elif len(sys.argv) == 3:
        try:
            number_to_compare = int(sys.argv[2], 16)
        except Exception as e:
            print("Number to compare is not passed as type int")
    if len(sys.argv) > 1:
        input_text = sys.argv[1] + ' '

    q_inp = Queue()
    q_out = Queue()

    tstart = time.time()

    # создание очереди из блоков для расчета crc64
    for i in range(steps_count):
        input_2 = bytes(input_text + chr(i + 48), 'utf-8')
        q_inp.put([crc64.xz(input_2), i + 48])

    threads = []
    for url in urls:
        # проверка доступности серверов flask и GPU, заданных в листе urls
        # при отсутствии ошибок создание потока для url 
        try:
            response = get(url + "/check", timeout=2)
            if response.content == b"Ok":
                threads.append(Thread(target=calculation_crc64, args=([url])))
            elif response.content == b"Not ok":
                print("No GPU on: ", url)
            else:
                raise Exception("Unknown error")
        except Exception as e:
            print("No answer from: ", url)

    if len(threads) == 0:
        raise SystemExit("No active flask")

    for thread in threads:
        thread.start()

    count1 = 0
    outval = 0
    min_res = hex((1 << 64) - 1)
    min_string = None
    total_count = 0

    while True:
        # обработка полученных ответов от flask (результат выполнения программы на cuda)
        if not q_out.empty():
            outval = q_out.get() 
            list_response = outval[1].decode('utf-8').split()
            total_count += int(list_response[3])
            count1 += 1
            if int(list_response[2], 16) < int(min_res, 16):
                    min_res = list_response[2]
                    min_string = input_text + outval[0] + list_response[1]
            if number_to_compare != None: 
                if int(min_res, 16)  <= number_to_compare:
                    print(f"Required crc64 found: {min_string}, {min_res}")
                    break
                if count1 == steps_count:
                    print(f"Required crc64 not found, the minimal one: {min_string}, {min_res}")
                    break
            elif count1 == steps_count:
                print(f"Minimal crc64: {min_string}, {min_res}")
                break
            
        else:
            time.sleep(0.1)

    # завершение выполнения потоков
    lock.acquire()
    end_work = True
    lock.release()
    for thread in threads:
        thread.join()

    total_time = time.time() - tstart
    print(f"Total time elapsed: {total_time:.3f} s, crc64 per second: {total_count/total_time/10**9:.3f} bln/s")