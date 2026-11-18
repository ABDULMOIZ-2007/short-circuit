#include "engine.hpp"
#include <iostream>
#include <fstream>
#include <iterator>
using namespace sc;
int checks=0;
void check(bool pass,const std::string&message){++checks;if(!pass)throw std::runtime_error(message);}
void near(double a,double b,const std::string&m){check(std::abs(a-b)<1e-9,m);}
Json project(const std::string&name){std::ifstream in("examples/"+name+".sc.json");return Json::parse(std::string(std::istreambuf_iterator<char>(in),{}));}
void kcl(const Json&frame){std::map<std::string,double>out;for(const auto&r:frame.at("components").array){auto id=r.at("id").text();const auto&tc=r.at("terminalCurrents").array;double total=0;for(size_t p=0;p<tc.size();++p){double i=tc[p].num();total+=i;out[id+":"+std::to_string(p)]+=i;}near(total,0,"Component terminal current conservation");}for(const auto&w:frame.at("wires").array){check(w.at("determinate").boolean,"Tree wire must have a unique current");double i=w.at("current").num();auto a=w.at("from").text(),b=w.at("to").text();if(out.count(a))out[a]+=i;if(out.count(b))out[b]-=i;}for(const auto&p:out)near(p.second,0,"Wire junction KCL "+p.first);}
int main(){try{
 SimulationEngine engine;
 auto divider=project("divider");auto result=engine.solve(Circuit(divider));kcl(result);
 for(const auto&w:result.at("wires").array)near(w.at("current").num(),.004,"Conventional current follows divider loop");
 divider["wires"].array[0]["from"]="R1:0";divider["wires"].array[0]["to"]="V1:0";result=engine.solve(Circuit(divider));near(result.at("wires").array[0].at("current").num(),-.004,"Reversed wire reverses signed current");kcl(result);
 divider=project("divider");divider["components"].array[0]["value"]=-12;result=engine.solve(Circuit(divider));for(const auto&w:result.at("wires").array)near(w.at("current").num(),-.004,"Reversed supply reverses flow");kcl(result);
 for(const auto&name:{"parallel","rc","rl","led","zener","switch","potentiometer","npn"})kcl(engine.solve(Circuit(project(name))));
 auto pnp=project("npn");pnp["components"].array[0]["value"]=-5;for(auto&c:pnp["components"].array)if(c.at("type").text()=="npn")c["type"]="pnp";kcl(engine.solve(Circuit(pnp)));
 result=engine.solve(Circuit(project("switch")));for(const auto&w:result.at("wires").array)check(std::abs(w.at("current").num())<1e-9,"Open switch leakage is below animation threshold");
 auto redundant=project("divider");redundant["wires"].push(redundant["wires"].array[0]);result=engine.solve(Circuit(redundant));check(!result.at("wires").array[0].at("determinate").boolean,"Parallel ideal-wire current is indeterminate");check(result.at("wires").array[0].at("current").kind==Json::Null,"Do not fabricate a cyclic wire current");check(!result.at("wires").array[4].at("determinate").boolean,"Both redundant paths are indeterminate");near(result.at("wires").array[1].at("current").num(),.004,"Bridge outside redundant cycle retains unique current");
 for(const auto&name:{"rc","rl"}){auto t=engine.transient(Circuit(project(name)),.05,20);for(const auto&sample:t.at("samples").array)kcl(sample);}
 std::cout<<"PASS: "<<checks<<" current direction, branching, junction and ambiguity checks\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}}
