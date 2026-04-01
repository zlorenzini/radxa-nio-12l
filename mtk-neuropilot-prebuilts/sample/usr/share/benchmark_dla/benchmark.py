import argparse
import os
import sys
import re
import numpy as np
import logging
import subprocess

available_backends = []

DIRTY = 1
CLEAR_DIRTY = 0

TIME = 'avg inference time:'
INIT_TIME = TIME + ' FAILED'

class ModelIO:
    def __init__(self):
        self.intput_size = (-1,-1,-1,-1)
        self.intput_type = 'unknown'
        self.output_count = 0
        self.recommand_compile_options = ''

def query_backends():
    batcmd = ('/home/radxa/repos/mtk-neuropilot-prebuilts/neuron/6/usr/sbin/ncc-tflite --arch=?')
    res = subprocess.run(batcmd, shell=True, check=False, executable='/bin/bash', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    result = res.stdout

    reg = re.compile(r"\n.*?- (.*)")
    match = re.findall(reg, result)
    output_count = 0
    if match:
        output_count = len(match)
    else:
        logging.error("FAIL to find backends")

    for i in range(output_count):
        available_backends.append(match[i])

def query_tflite_model_io_info(model):
    # find input size and output count of tflite model
    ret = ModelIO()

    intput_size = (-1,-1,-1,-1)
    intput_type = 'kTfLiteUInt8'
    output_count = 0
    batcmd = ('/home/radxa/repos/mtk-neuropilot-prebuilts/neuron/6/usr/sbin/ncc-tflite --show-io-info %s' % model )
    res = subprocess.run(batcmd, shell=True, check=True, executable='/bin/bash', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    result = res.stdout
    
    logging.debug(result)

    # find output count
    match = re.search(r'of output tensors: (\d+)', result)
    if match:
        output_count = int(match.group(1))
    else:
        logging.error("FAIL to find output count of model")
        return ret

    ret.output_count = output_count

    # find input size
    tmp = result.partition("# of output tensors")[0]
    match = re.search(r'Shape: {(\d+),(\d+),(\d+),(\d+)}', tmp)
    if match:
        intput_size = ( int(match.group(1)), int(match.group(2)), int(match.group(3)), int(match.group(4)) )
    else:
        logging.error("FAIL to find input size of model")
        return ret

    ret.intput_size = intput_size

    # find input type
    match = re.search(r'Type: (\w+)', tmp)
    if match:
        intput_type = (match.group(1))
    else:
        logging.error("FAIL to find input type of model")
        return ret

    ret.intput_type = intput_type
    if intput_type == 'kTfLiteFloat32':
        ret.recommand_compile_options = ' --relax-fp32 '

    return ret

def query_dla_model_io_info(model):
    # find input size and output count of dla model
    ret = ModelIO()

    batcmd = ('neuronrt -a %s -d' % model)
    result = os.popen(batcmd).read()

	# find input size
    match = re.search(r'Handle = 0, <(\d+) x (\d+) x (\d+) x (\d+)>', result)
    if match:
        intput_size = ( int(match.group(1)), int(match.group(2)), int(match.group(3)), int(match.group(4)) )
    else:
        logging.error("FAIL to find input size of model")
        return

    ret.intput_size = intput_size

    # find output count
    tmp = result.partition("Output")[2]
    match = re.findall('Handle = ', tmp)
    if match:
        output_count = len(match)
    else:
        logging.error("FAIL to find output scountize of model")
        return

    ret.output_count = output_count

    return ret


def gen_input_bin(model_io, filename):
    # generate input data, format can be uint8 or float32
    ndarray = np.random.randint(0, high=255, size=model_io.intput_size, dtype=np.uint8)
    if model_io.intput_type == 'kTfLiteFloat32':
        ndarray = np.float32(ndarray)/255.0
    ndarray.tofile(filename)


def tflite_2_dla(tflite_model, target, dla_model, compile_options=""):
    # compile for specific target
    if os.path.exists(dla_model):
        return

    batcmd = ('ncc-tflite -arch %s %s -o %s %s' % (target, tflite_model, dla_model, compile_options) )
    res = subprocess.run(batcmd, shell=True, check=True, executable='/bin/bash', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    result = res.stdout
    logging.debug(result)

def benchmark_tflite_model_auto(model, count=100, compile_options="", cache_dla=False, profile=False):
    tflite_target_list = []
    for i in range(len(available_backends)):
      if available_backends[i] != 'tflite_cpu':
        element = [available_backends[i], '', CLEAR_DIRTY]
        tflite_target_list.append(element)

    for element in tflite_target_list:
        result = ''

        target = element[0];

        element[1] = '%s, %s, %s' % (model, target, INIT_TIME)
        element[2] = CLEAR_DIRTY

        dla = model.replace('.tflite', "-"+ target + '.dla')
        tflite_2_dla(model, target, dla, compile_options)
        if not os.path.exists(dla):
            logging.error("FAIL to convert model to dla with target %s, %s" % (target, model))
            continue

        # find input size and output count of model
        modeil_io = query_tflite_model_io_info(model)

        # gen rand input.bin
        input_bin = 'input.bin'
        gen_input_bin(modeil_io, input_bin)

        # inference
        batcmd = 'neuronrt -m hw -a %s -c %s -b 100 -i %s ' % (dla, count, input_bin)
        for i in range(modeil_io.output_count):
            batcmd = batcmd + (' -o output_%s.bin ' % i)

        if profile is True:
            logging.info("%s, %s, inference start" % (model, target))

        res = subprocess.run(batcmd, shell=True, check=True, executable='/bin/bash', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)

        if profile is True:
            logging.info("%s, %s, inference stop" % (model, target))
            print(res.stdout)
            
        result = res.stdout
        logging.debug(result)

        # find 'Total inference time' in output log
        match = re.search(r'Total inference time = (\d+)', result)
        if match:
            time = float(match.group(1))
            # calculate avg inference time
            avg_time = time / count
            element[1] = '%s, %s, %s %s' % (model, target, TIME, avg_time)
            element[2] = DIRTY;
            logging.info(element[1])

        if not cache_dla:
            os.remove(dla)



def benchmark_tflite_model(model, target, count=100, compile_options="", cache_dla=False, profile=False):

    dla = model.replace('.tflite', "-"+ target + '.dla')
    tflite_2_dla(model, target, dla, compile_options)
    if not os.path.exists(dla):
        logging.error("FAIL to convert model to dla with target %s, %s" % (target, model))
        return

    # find input size and output count of model
    modeil_io = query_tflite_model_io_info(model)

    # gen rand input.bin
    input_bin = 'input.bin'
    gen_input_bin(modeil_io, input_bin)


    batcmd = 'neuronrt -m hw -a %s -c %s -b 100 -i %s ' % (dla, count, input_bin)
    for i in range(modeil_io.output_count):
        batcmd = batcmd + (' -o output_%s.bin ' % i)

    if profile is True:
        logging.info("%s, %s, inference start" % (model, target))

    res = subprocess.run(batcmd, shell=True, check=True, executable='/bin/bash', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)

    if profile is True:
        logging.info("%s, %s, inference stop" % (model, target))
        print(res.stdout)

    result = res.stdout     
    logging.debug(result)

    if not cache_dla:
        os.remove(dla)

    # find 'Total inference time' in output log
    match = re.search(r'Total inference time = (\d+)', result)
    if match:
        time = float(match.group(1))
        # calculate avg inference time
        avg_time = time / count
    else:
        logging.error("FAIL to find avg inference time of model")
        return

    logging.info('%s, %s, avg inference time: %s' % (model, target, avg_time))



def benchmark_dla_model(model, count=100, profile=False):
    result = ''

    os.environ["MTKNN_ENABLE_PROFILER"] = "0"

    # find input size and output count of model
    modeil_io = query_dla_model_io_info(model)

    if profile is True:
        os.environ["MTKNN_ENABLE_PROFILER"] = "1"

    # gen rand input.bin
    input_bin = 'input.bin'
    gen_input_bin(modeil_io, input_bin)

    # inference
    batcmd = 'neuronrt -m hw -a %s -c %s -b 100 -i %s ' % (model, count, input_bin)
    for i in range(modeil_io.output_count):
        batcmd = batcmd + (' -o output_%s.bin ' % i)

    if profile is True:
        logging.info("%s, inference start" % model)

    res = subprocess.run(batcmd, shell=True, check=True, executable='/bin/bash', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)

    if profile is True:
        logging.info("%s, inference stop" % model)
        print(res.stdout)

    result = res.stdout
    logging.debug(result)

    # find 'Total inference time' in output log
    match = re.search(r'Total inference time = (\d+)', result)
    if match:
        time = float(match.group(1))
        # calculate avg inference time
        avg_time = time / count
    else:
        logging.error("FAIL to find avg inference time of model")
        return

    logging.info('%s, avg inference time: %s' % (model, avg_time))


query_backends()

# argument parser
parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter)

parser.add_argument(
        '--auto',
        action='store_true',
        help='Auto run, find all models in current folder and inference them one by one. It will delete dla file after inference and it will ignore options: --file and --target')

parser.add_argument(
        '--stress',
        action='store_true',
        help='Stress test, find all models in current folder and inference them one by one. It will not delete dla file after inference and it will ignore options: --auto, --file and --target')

parser.add_argument(
        '--file',
        default="",
        help='Input a tflite model to inference. it will be executed with option: --target')

parser.add_argument(
        '--target',
        default=available_backends[0],
        choices=available_backends,
        help='Choose a backends to inference. Default: %s' % available_backends[0])

parser.add_argument(
        '--count',
        default=100,
        type=int,
        help='How many times of inference. Default: 100')

parser.add_argument(
        '--profile',
        action='store_true',
        help='print profile information')

parser.add_argument(
        '--options',
        default="",
        help='Add additional ncc-tflite options. Please find options by \'ncc-tflite -h\'\n'
             'Ex. --options=\'--relax-fp32\'')

args = parser.parse_args()

# get python script location
head, tail = os.path.split(__file__)
pwd = os.path.join(head, '')


# preapre log
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

if args.stress is False:
    sh = logging.FileHandler(pwd + "/benchmark.log", mode='w')
    fh = logging.StreamHandler(sys.stdout)
    logging.getLogger('').addHandler(sh)
    logging.getLogger('').addHandler(fh)

if args.profile is True:
    os.environ["MTKNN_ENABLE_PROFILER"] = "1"
else:
    os.environ["MTKNN_ENABLE_PROFILER"] = "0"

if args.auto is True or args.stress is True:
    cache_dla = False
    if args.stress is True:
        cache_dla = True

    # auto run, find all models in current folder and inference them one by one
    for file in os.listdir(pwd):
        if file.endswith('.tflite'):
            modeil_io = query_tflite_model_io_info(pwd+file)
            compile_options = args.options + modeil_io.recommand_compile_options
            benchmark_tflite_model_auto(pwd+file, args.count, compile_options, cache_dla, args.profile)

else:
    if os.path.exists(args.file):
        if args.file.endswith('.tflite'):
            modeil_io = query_tflite_model_io_info(args.file)
            compile_options = args.options + modeil_io.recommand_compile_options
            benchmark_tflite_model(args.file, args.target, args.count, compile_options, False, args.profile)
        elif args.file.endswith('.dla'):
            benchmark_dla_model(args.file, args.count, args.profile)
    else:
        logging.error('Error to load model %s', args.file)
