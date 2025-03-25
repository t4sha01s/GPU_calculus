from flask import Flask, jsonify, request
import time
from subprocess import run, Popen, PIPE
 
app = Flask(__name__)
 
# вызов программы для расчета crc64 на cuda
@app.route('/calc64', methods=['GET'])
def run_crc64():    
    crc_pref = request.args.get("crc_pref", type=str)
    result = run("./crc64_cuda calc " + crc_pref, shell=True, capture_output = True, encoding='utf-8')
    return result.stdout

# вызов программы для проверки работоспособности GPU
@app.route('/check', methods=['GET'])
def check_work():
    result = run("./crc64_cuda check", shell=True, capture_output = True, encoding='cp866')
    device_count_returned = int(result.stdout.split()[1])
    ret_val = "Ok" if device_count_returned > 0 else  "Not ok"
    return ret_val
 
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5101, debug=True)