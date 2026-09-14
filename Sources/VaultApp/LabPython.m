#import "LabPython.h"
#import <Python/Python.h>
#include <stdatomic.h>
static atomic_bool cancelled = false;
static VaultGPUCallback gpuCallback,modelCallback;
static PyObject *dispatcher;
static PyObject *isCancelled(PyObject *self, PyObject *args) { return PyBool_FromLong(atomic_load(&cancelled)); }
static PyObject *gpuRequest(PyObject *self, PyObject *args) {
    const char *request;
    if (!PyArg_ParseTuple(args, "s", &request)) return NULL;
    if (!gpuCallback) {PyErr_SetString(PyExc_RuntimeError,"Native GPU is unavailable");return NULL;}
    char *answer=gpuCallback(request);
    if(!answer) {PyErr_SetString(PyExc_RuntimeError,"GPU request failed");return NULL;}
    PyObject *result=PyUnicode_FromString(answer);free(answer);return result;
}
static PyObject *modelRequest(PyObject *self, PyObject *args) {
    const char *request;
    if (!PyArg_ParseTuple(args, "s", &request)) return NULL;
    if (!modelCallback) {PyErr_SetString(PyExc_RuntimeError,"Vault local models are unavailable");return NULL;}
    char *answer;
    Py_BEGIN_ALLOW_THREADS
    answer=modelCallback(request);
    Py_END_ALLOW_THREADS
    if(!answer) {PyErr_SetString(PyExc_RuntimeError,"Local model request failed");return NULL;}
    PyObject *result=PyUnicode_FromString(answer);free(answer);return result;
}
static PyMethodDef nativeMethods[]={{"model",modelRequest,METH_VARARGS,"Use installed Vault models on this device."},{"cancelled",isCancelled,METH_NOARGS,"Return cancellation state."},{"gpu",gpuRequest,METH_VARARGS,"Execute an MLX graph on this device."},{NULL,NULL,0,NULL}};
static struct PyModuleDef nativeModule={PyModuleDef_HEAD_INIT,"_vault_native",NULL,-1,nativeMethods};
static PyObject *PyInit_vault_native(void){return PyModule_Create(&nativeModule);}
@implementation LabPython
+(void)setModelCallback:(VaultGPUCallback)callback {modelCallback=callback;}
+(void)setGPUCallback:(VaultGPUCallback)callback {gpuCallback=callback;}
+(NSString *)initializeAt:(NSString *)bundle error:(NSString **)error {
    if(dispatcher)return @"ready";
    PyImport_AppendInittab("_vault_native",PyInit_vault_native);
    PyPreConfig preconfig;PyPreConfig_InitIsolatedConfig(&preconfig);preconfig.utf8_mode=1;
    PyStatus s=Py_PreInitialize(&preconfig);
    if(PyStatus_Exception(s)){if(error)*error=@"Python UTF-8 initialization failed";return nil;}
    PyConfig config;PyConfig_InitIsolatedConfig(&config);
    config.write_bytecode=0;config.install_signal_handlers=0;config.use_environment=0;
    NSString *home=[bundle stringByAppendingPathComponent:@"python"];
    s=PyConfig_SetBytesString(&config,&config.home,home.UTF8String);
    if(!PyStatus_Exception(s))s=PyConfig_SetBytesString(&config,&config.executable,NSBundle.mainBundle.executablePath.UTF8String);
    if(!PyStatus_Exception(s))s=Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if(PyStatus_Exception(s)){if(error)*error=[NSString stringWithUTF8String:s.err_msg ?: "Python initialization failed"];return nil;}
    PyObject *path=PySys_GetObject("path");
    for(NSString *folder in @[@"lab-python",@"lab-packages"]) {
        PyObject *entry=PyUnicode_FromString([bundle stringByAppendingPathComponent:folder].UTF8String);
        PyList_Insert(path,0,entry);Py_DECREF(entry);
    }
    PyObject *module=PyImport_ImportModule("vault_kernel");
    if(module){dispatcher=PyObject_GetAttrString(module,"dispatch_json");Py_DECREF(module);}
    if(!dispatcher){PyErr_Print();if(error)*error=@"Could not initialize the bundled lab kernel";PyEval_SaveThread();return nil;}
    PyEval_SaveThread();return @"ready";
}
+(NSString *)dispatch:(NSString *)request {
    atomic_store(&cancelled,false);
    PyGILState_STATE state=PyGILState_Ensure();
    PyObject *arg=PyUnicode_FromString(request.UTF8String);
    PyObject *result=PyObject_CallFunctionObjArgs(dispatcher,arg,NULL);Py_DECREF(arg);
    NSString *answer;
    if(result){const char *utf8=PyUnicode_AsUTF8(result);answer=utf8?[NSString stringWithUTF8String:utf8]:nil;Py_DECREF(result);}
    if(!answer){PyErr_Print();answer=@"{\"error\":\"The Python kernel could not complete this request\"}";}
    PyGILState_Release(state);return answer;
}
+(void)cancel {atomic_store(&cancelled,true);}
@end
