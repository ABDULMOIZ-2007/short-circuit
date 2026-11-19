#include "short_circuit.h"
#include "engine.hpp"
#include <cstring>
extern "C" SC_API char* sc_request(const char* request) {
 std::string response;
 try {if(!request)throw std::runtime_error("Null request.");response=sc::execute(sc::Json::parse(request)).dump();}
 catch(const std::exception&e){auto out=sc::Json::obj();out["ok"]=false;out["error"]=e.what();response=out.dump();}
 catch(...){response="{\"ok\":false,\"error\":\"Unexpected native error.\"}";}
 char* buffer=new char[response.size()+1];std::memcpy(buffer,response.c_str(),response.size()+1);return buffer;
}
extern "C" SC_API void sc_free(char* response){delete[] response;}

