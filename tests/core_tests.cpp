#include "engine.hpp"
#include "short_circuit.h"
#include <cstdio>
#include <iostream>
#include <functional>
#include <cstdlib>
#ifndef SC_TEST_STORAGE
#define SC_TEST_STORAGE "tests/test-output"
#endif
using sc::Json;
int checks=0;
void check(bool ok,const char* message){++checks;if(!ok)throw std::runtime_error(message);}
void near(double a,double b,double tol=1e-9){check(std::abs(a-b)<=tol,"Numeric expectation failed.");}
Json example(const char* name){std::ifstream in(std::string("examples/")+name+".sc.json");if(!in)throw std::runtime_error("Run tests from the project root.");std::ostringstream s;s<<in.rdbuf();return Json::parse(s.str());}
Json call(Json request){auto text=request.dump();char* ptr=sc_request(text.c_str());check(ptr!=nullptr,"Null FFI response");auto r=Json::parse(ptr);sc_free(ptr);return r;}
Json sim(Json project){Json r=Json::obj();r["op"]="simulate";r["project"]=project;auto out=call(r);check(out.at("ok").boolean,"Simulation failed");return out.at("result");}
void fails(Json project){Json r=Json::obj();r["op"]="simulate";r["project"]=project;check(!call(r).at("ok").boolean,"Invalid circuit accepted");}
int main(){
 try{
  auto divider=example("divider"),parallel=example("parallel"),rc=example("rc");
  auto r=sim(divider);near(r.at("components").array[2].at("voltage").num(),8);near(r.at("components").array[0].at("current").num(),-.004);near(r.at("dissipatedPower").num(),.048);near(r.at("powerBalance").num(),0);
  auto p=sim(parallel);near(p.at("components").array[0].at("current").num(),-.018);
  auto dc=sim(rc);near(dc.at("components").array[2].at("voltage").num(),5);near(dc.at("components").array[2].at("current").num(),0);
  Json req=Json::obj();req["op"]="transient";req["project"]=rc;req["duration"]=.05;req["steps"]=1000;auto tr=call(req);check(tr.at("ok").boolean,"Transient failed");auto&samples=tr.at("result").at("samples").array;
  near(samples.front().at("components").array[2].at("voltage").num(),0);near(samples.back().at("components").array[2].at("voltage").num(),5*(1-std::exp(-5)),.0005);
  for(size_t i=1;i<samples.size();++i){check(samples[i].at("components").array[2].at("voltage").num()>=samples[i-1].at("components").array[2].at("voltage").num(),"RC is not monotonic");near(samples[i].at("powerBalance").num(),0,1e-10);}
  auto invalid=divider;invalid["components"].array[1]["value"]=0;fails(invalid);
  invalid=divider;invalid["components"].array.push_back(invalid["components"].array[0]);fails(invalid);
  invalid=divider;invalid["wires"].array[0]["from"]="absent:0";fails(invalid);
  invalid=divider;auto w=Json::obj();w["from"]="V1:0";w["to"]="V1:1";invalid["wires"].push(w);fails(invalid);
  invalid=divider;invalid["components"].array.erase(invalid["components"].array.begin()+3);fails(invalid);
  invalid=divider;invalid["components"].array[1]["value"]=1e12;invalid["components"].array[2]["value"]=1e12;near(sim(invalid).at("components").array[2].at("voltage").num(),6,1e-6);
  auto quoted=Json::parse("{\"title\":\"Moiz \\\"lab\\\" \\u03a9 \\ud83d\\ude00\"}");check(Json::parse(quoted.dump()).at("title").text()==quoted.at("title").text(),"Unicode JSON roundtrip");
  for(auto bad:{"{\"x\":1,\"x\":2}","{\"x\":01}","{\"x\":1e}","[1,]","{\"x\":NaN}","{\"x\":\"\\ud800\"}"}){bool rejected=false;try{Json::parse(bad);}catch(...){rejected=true;}check(rejected,"Malformed JSON accepted");}
  req=Json::obj();req["op"]="save";req["directory"]=SC_TEST_STORAGE;auto saved=divider;saved["id"]="sc-test-roundtrip";saved["title"]="Moiz Unicode Ω";req["project"]=saved;check(call(req).at("ok").boolean,"Save failed");
  req["op"]="load";req["id"]="sc-test-roundtrip";auto loaded=call(req);check(loaded.at("project").at("title").text()==saved.at("title").text(),"Saved title changed");near(sim(loaded.at("project")).at("components").array[2].at("voltage").num(),8);
  req["id"]="../outside";check(!call(req).at("ok").boolean,"Traversal accepted");
  std::remove((std::string(SC_TEST_STORAGE)+"/workspace.json").c_str());
  req=Json::obj();req["op"]="restore";req["directory"]=SC_TEST_STORAGE;
  check(call(req).at("project").kind==Json::Null,"Fresh install must have no recovery workspace");
  req["op"]="checkpoint";req["project"]=saved;req["dirty"]=true;check(call(req).at("ok").boolean,"Checkpoint failed");
  req["op"]="restore";auto restored=call(req);check(restored.at("dirty").boolean,"Unsaved status lost");
  near(sim(restored.at("project")).at("components").array[2].at("voltage").num(),8);
  auto unfinished=saved;unfinished["components"]=Json::arr();unfinished["wires"]=Json::arr();
  req["op"]="checkpoint";req["project"]=unfinished;req["dirty"]=false;check(call(req).at("ok").boolean,"Empty circuit recovery failed");
  req["op"]="restore";restored=call(req);check(restored.at("project").at("components").array.empty(),"Recovery did not replace old workspace");check(!restored.at("dirty").boolean,"Saved status lost");
  req["op"]="list";check(call(req).at("projects").array.size()==1,"Recovery must not appear on project shelf");
  std::remove((std::string(SC_TEST_STORAGE)+"/workspace.json").c_str());
  std::remove((std::string(SC_TEST_STORAGE)+"/sc-test-roundtrip.sc.json").c_str());std::remove((std::string(SC_TEST_STORAGE)+"/index.json").c_str());
  std::cout<<"PASS: "<<checks<<" native numeric, topology, JSON, FFI and persistence checks\n";return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}
}

