#include "engine.hpp"
#include <iostream>
using sc::Json;
int checks=0;
void check(bool ok,const char* message){++checks;if(!ok)throw std::runtime_error(message);}
void near(double a,double b,double tolerance=1e-8){if(std::abs(a-b)>tolerance){std::cerr<<"Actual "<<a<<" expected "<<b<<"\n";throw std::runtime_error("Numeric expectation failed");}++checks;}
Json project(){Json p=Json::obj();p["schema"]=1;p["id"]="extended-tests";p["title"]="Extended tests";p["components"]=Json::arr();p["wires"]=Json::arr();return p;}
void part(Json&p,const char*id,const char*type,double value){Json c=Json::obj();c["id"]=id;c["label"]=id;c["type"]=type;c["value"]=value;p["components"].push(c);}
void wire(Json&p,const char*a,const char*b){Json w=Json::obj();w["from"]=a;w["to"]=b;p["wires"].push(w);}
Json result(const Json&p){return sc::SimulationEngine().solve(sc::Circuit(p));}
const Json& row(const Json&r,const char*id){for(auto&v:r.at("components").array)if(v.at("id").text()==id)return v;throw std::runtime_error("Reading absent");}
Json series(const char*type,double value,double supply=12,double resistance=1000,bool reverse=false){
 auto p=project();part(p,"G","ground",0);part(p,"V","voltage",supply);part(p,"R","resistor",resistance);part(p,"X",type,value);
 wire(p,"V:1","G:0");wire(p,"V:0","R:0");
 wire(p,"R:1",reverse?"X:1":"X:0");wire(p,reverse?"X:0":"X:1","G:0");return p;
}
int main(){
 try{
  for(const char*type:{"diode","led"}){
   auto p=project();part(p,"G","ground",0);part(p,"I","current",.001);part(p,"D",type,std::string(type)=="led"?2:.7);
   wire(p,"I:0","G:0");wire(p,"I:1","D:0");wire(p,"D:1","G:0");
   auto r=result(p);near(row(r,"D").at("voltage").num(),std::string(type)=="led"?2:.7,1e-7);near(row(r,"D").at("current").num(),.001,1e-10);near(r.at("powerBalance").num(),0,1e-10);
   auto loaded=result(series(type,std::string(type)=="led"?2:.7));
   auto&d=row(loaded,"X");near(d.at("voltage").num()+1000*d.at("current").num(),12,1e-8);near(loaded.at("powerBalance").num(),0,1e-8);
   auto reverse=result(series(type,std::string(type)=="led"?2:.7,12,1000,true));check(std::abs(row(reverse,"X").at("current").num())<1e-10,"Reverse diode leakage excessive");
  }
  auto z=result(series("zener",5.1,12,1000,true));near(row(z,"X").at("voltage").num(),-(12*10+5.1*1000)/1010,1e-7);near(z.at("powerBalance").num(),0,1e-8);
  auto closed=result(series("switch",1));near(row(closed,"R").at("current").num(),12/1000.001,1e-10);
  auto open=result(series("switch",0));check(std::abs(row(open,"R").at("current").num())<1e-9,"Open switch carries load current");
  auto pot=project();part(pot,"G","ground",0);part(pot,"V","voltage",12);part(pot,"P","potentiometer",10000);pot["components"].array.back()["setting"]=.25;
  wire(pot,"V:0","P:0");wire(pot,"V:1","G:0");wire(pot,"P:1","G:0");
  auto p=result(pot);near(p.at("nodeVoltages").at("P:2").num(),9);near(p.at("powerBalance").num(),0,1e-10);
  part(pot,"RL","resistor",10000);wire(pot,"RL:0","P:2");wire(pot,"RL:1","G:0");p=result(pot);near(p.at("nodeVoltages").at("P:2").num(),12*(7500.0*10000/17500)/(2500+7500.0*10000/17500));near(p.at("powerBalance").num(),0,1e-10);
  for(bool pnp:{false,true}){
   auto b=project();part(b,"G","ground",0);part(b,"V","voltage",5);part(b,"VB","voltage",pnp?4.35:.65);part(b,"R","resistor",1000);part(b,"Q",pnp?"pnp":"npn",100);
   wire(b,"V:1","G:0");wire(b,"VB:1","G:0");wire(b,"VB:0","Q:2");
   wire(b,"R:1","Q:0");wire(b,"R:0",pnp?"G:0":"V:0");wire(b,"Q:1",pnp?"V:0":"G:0");
   auto r=result(b);const auto&q=row(r,"Q");double ic=q.at("collectorCurrent").num(),ib=q.at("baseCurrent").num(),ie=q.at("emitterCurrent").num();
   check(pnp?ic<0:ic>0,"Transistor collector polarity");near(ic/ib,100,1e-5);near(ic+ib+ie,0,1e-12);near(q.at("vbe").num(),pnp?-.65:.65,1e-8);near(r.at("powerBalance").num(),0,1e-8);check(q.at("state").text()=="Active","Transistor should be active");
  }
  auto rl=series("inductor",1,5,100);auto dc=result(rl);near(row(dc,"X").at("current").num(),.05);near(row(dc,"X").at("voltage").num(),0);
  auto transient=sc::SimulationEngine().transient(sc::Circuit(rl),.05,1000);auto&frames=transient.at("samples").array;
  near(row(frames.front(),"X").at("current").num(),0);near(row(frames.front(),"X").at("voltage").num(),5);
  near(row(frames.back(),"X").at("current").num(),.05*(1-std::exp(-5)),.000005);
  double last=0;for(auto&f:frames){double current=row(f,"X").at("current").num();check(current>=last,"RL response is not monotonic");last=current;near(f.at("powerBalance").num(),0,1e-8);}
  auto rlc=series("inductor",.01,5,100);part(rlc,"C","capacitor",.000001);rlc["wires"].array.pop_back();wire(rlc,"X:1","C:0");wire(rlc,"C:1","G:0");
  auto ring=sc::SimulationEngine().transient(sc::Circuit(rlc),.01,1000);double highest=0;
  for(auto&f:ring.at("samples").array){near(f.at("powerBalance").num(),0,1e-8);highest=std::max(highest,row(f,"C").at("voltage").num());}
  check(highest>5.5&&highest<6,"RLC overshoot is outside the expected damping range");near(row(ring.at("samples").array.back(),"C").at("voltage").num(),5,.001);
  std::cout<<"PASS: "<<checks<<" extended semiconductor, switch, potentiometer, RL and RLC checks\n";
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
