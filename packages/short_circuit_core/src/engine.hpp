#pragma once
#include <functional>
#include <algorithm>
#include <cmath>
#include <cctype>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
namespace sc {
class Json {
public:
 enum Kind {Null,Number,Boolean,String,Array,Object} kind=Null;
 double number=0; bool boolean=false; std::string string;
 std::vector<Json> array; std::map<std::string,Json> object;
 Json()=default;
 Json(double n):kind(Number),number(n){if(!std::isfinite(n))throw std::runtime_error("Non-finite number.");}
 Json(int n):Json(double(n)){} Json(bool b):kind(Boolean),boolean(b){}
 Json(std::string s):kind(String),string(std::move(s)){} Json(const char*s):Json(std::string(s)){}
 static Json obj(){Json j;j.kind=Object;return j;} static Json arr(){Json j;j.kind=Array;return j;}
 Json& operator[](const std::string&k){if(kind==Null)kind=Object;if(kind!=Object)throw std::runtime_error("Expected object.");return object[k];}
 const Json& at(const std::string&k)const{auto i=object.find(k);if(kind!=Object||i==object.end())throw std::runtime_error("Missing field: "+k);return i->second;}
 const Json& get(const std::string&k)const{static Json empty;auto i=object.find(k);return i==object.end()?empty:i->second;}
 std::string text(std::string fallback="")const{return kind==String?string:fallback;}
 double num(double fallback=0)const{return kind==Number?number:fallback;}
 void push(Json j){if(kind!=Array)throw std::runtime_error("Expected array.");array.push_back(std::move(j));}
 static std::string quote(const std::string&s){std::ostringstream o;o<<'"';for(unsigned char c:s){switch(c){case '"':o<<"\\\"";break;case '\\':o<<"\\\\";break;case '\n':o<<"\\n";break;case '\r':o<<"\\r";break;case '\t':o<<"\\t";break;default:if(c<32)o<<"\\u"<<std::hex<<std::setw(4)<<std::setfill('0')<<int(c)<<std::dec;else o<<c;}}o<<'"';return o.str();}
 std::string dump()const{std::ostringstream o;o<<std::setprecision(15);switch(kind){case Null:return "null";case Boolean:return boolean?"true":"false";case Number:o<<number;return o.str();case String:return quote(string);case Array:{o<<'[';bool first=true;for(auto&v:array){if(!first)o<<',';first=false;o<<v.dump();}o<<']';break;}case Object:{o<<'{';bool first=true;for(auto&v:object){if(!first)o<<',';first=false;o<<quote(v.first)<<':'<<v.second.dump();}o<<'}';break;}}return o.str();}
 static Json parse(const std::string&input){
  if(input.size()>2097152)throw std::runtime_error("Project exceeds 2 MB.");
  struct Parser{
   const std::string&s;size_t p=0;
   void ws(){while(p<s.size()&&std::isspace((unsigned char)s[p]))++p;}
   char take(){if(p>=s.size())throw std::runtime_error("Unexpected end of JSON.");return s[p++];}
   unsigned hex(){unsigned n=0;for(int i=0;i<4;++i){char c=take();n*=16;if(c>='0'&&c<='9')n+=c-'0';else if(c>='a'&&c<='f')n+=c-'a'+10;else if(c>='A'&&c<='F')n+=c-'A'+10;else throw std::runtime_error("Invalid Unicode escape.");}return n;}
   void utf(std::string&o,unsigned c){if(c<128)o+=char(c);else if(c<2048){o+=char(0xc0|(c>>6));o+=char(0x80|(c&63));}else if(c<65536){o+=char(0xe0|(c>>12));o+=char(0x80|((c>>6)&63));o+=char(0x80|(c&63));}else{o+=char(0xf0|(c>>18));o+=char(0x80|((c>>12)&63));o+=char(0x80|((c>>6)&63));o+=char(0x80|(c&63));}}
   std::string str(){if(take()!='"')throw std::runtime_error("Expected string.");std::string o;while(true){char c=take();if(c=='"')return o;if((unsigned char)c<32)throw std::runtime_error("Invalid string.");if(c!='\\'){o+=c;continue;}switch(c=take()){case '"':case '\\':case '/':o+=c;break;case 'n':o+='\n';break;case 'r':o+='\r';break;case 't':o+='\t';break;case 'b':o+='\b';break;case 'f':o+='\f';break;case 'u':{unsigned cp=hex();if(cp>=0xd800&&cp<=0xdbff){if(take()!='\\'||take()!='u')throw std::runtime_error("Missing surrogate.");unsigned low=hex();if(low<0xdc00||low>0xdfff)throw std::runtime_error("Invalid surrogate.");cp=0x10000+((cp-0xd800)<<10)+low-0xdc00;}else if(cp>=0xdc00&&cp<=0xdfff)throw std::runtime_error("Unexpected surrogate.");utf(o,cp);break;}default:throw std::runtime_error("Invalid escape.");}}}
   Json value(int depth=0){if(depth>64)throw std::runtime_error("JSON nesting limit.");ws();if(p>=s.size())throw std::runtime_error("Empty JSON.");char c=s[p];
    if(c=='"')return Json(str());
    if(c=='{'||c=='['){++p;Json v=c=='{'?Json::obj():Json::arr();char end=c=='{'?'}':']';ws();if(p<s.size()&&s[p]==end){++p;return v;}while(true){ws();if(c=='{'){auto k=str();ws();if(take()!=':')throw std::runtime_error("Expected colon.");if(v.object.count(k))throw std::runtime_error("Duplicate key.");v[k]=value(depth+1);}else v.push(value(depth+1));ws();char x=take();if(x==end)return v;if(x!=',')throw std::runtime_error("Expected comma.");}}
    for(auto word:{"null","true","false"}){std::string w(word);if(s.compare(p,w.size(),w)==0){p+=w.size();return w=="null"?Json():Json(w=="true");}}
    size_t start=p;if(s[p]=='-')++p;if(p>=s.size())throw std::runtime_error("Invalid number.");if(s[p]=='0')++p;else{if(s[p]<'1'||s[p]>'9')throw std::runtime_error("Invalid number.");while(p<s.size()&&std::isdigit((unsigned char)s[p]))++p;}
    if(p<s.size()&&s[p]=='.'){++p;size_t q=p;while(p<s.size()&&std::isdigit((unsigned char)s[p]))++p;if(q==p)throw std::runtime_error("Invalid fraction.");}
    if(p<s.size()&&(s[p]=='e'||s[p]=='E')){++p;if(p<s.size()&&(s[p]=='+'||s[p]=='-'))++p;size_t q=p;while(p<s.size()&&std::isdigit((unsigned char)s[p]))++p;if(q==p)throw std::runtime_error("Invalid exponent.");}return Json(std::stod(s.substr(start,p-start)));
   }
  }p{input};Json j=p.value();p.ws();if(p.p!=input.size())throw std::runtime_error("Trailing JSON content.");return j;
 }
};
struct Node{std::string terminal;int net=-1;};
struct Wire{std::string from,to;};
struct Stamp{
 std::vector<std::vector<double>>&a;std::vector<double>&z;const std::vector<double>&previous;double dt=0;bool initial=false;int branch=-1;
 const std::vector<double>*estimate=nullptr;const std::map<std::string,double>*history=nullptr;
 void add(int r,int c,double v){if(r>=0&&c>=0)a.at(r).at(c)+=v;}
 void rhs(int r,double v){if(r>=0)z.at(r)+=v;}
 void conductance(int p,int n,double g){add(p,p,g);add(n,n,g);add(p,n,-g);add(n,p,-g);}
 void branchKcl(int p,int n){add(p,branch,1);add(n,branch,-1);}
 void voltage(int p,int n,double v){branchKcl(p,n);add(branch,p,1);add(branch,n,-1);rhs(branch,v);}
 double old(int i)const{return i<0?0:previous.at(i);}
 double now(int i)const{return i<0||!estimate?0:estimate->at(i);}
 double oldCurrent(const std::string&id)const{if(!history)return 0;auto i=history->find(id);return i==history->end()?0:i->second;}
 void junction(int p,int n,double current,double g){double equivalent=current-g*(now(p)-now(n));conductance(p,n,g);rhs(p,-equivalent);rhs(n,equivalent);}
};
struct JunctionValue{double current,g;};
inline JunctionValue junctionValue(double v,double saturation,double vt){
 double u=v/vt,e;
 if(u>80)e=std::exp(80.0)*(1+u-80);else e=std::exp(std::max(-80.0,u));
 double slope=saturation*(u>80?std::exp(80.0):e)/vt;
 return {saturation*(e-1),slope};
}
class Component{
 std::string id_,label_;double value_;int p_=-1,n_=-1,third_=-1;
public:
 Component(std::string id,std::string label,double v):id_(std::move(id)),label_(std::move(label)),value_(v){setValue(v);}
 virtual ~Component()=default;
 const std::string&id()const{return id_;}const std::string&label()const{return label_;}double value()const{return value_;}
 int positive()const{return p_;}int negative()const{return n_;}int third()const{return third_;}
 void connect(int p,int n,int third=-1){p_=p;n_=n;third_=third;}
 void setValue(double v){if(!std::isfinite(v)||std::abs(v)>1e12)throw std::runtime_error("Value outside supported range.");value_=v;}
 virtual const char*type()const=0;virtual void validate()const=0;virtual void stamp(Stamp&)const=0;
 virtual int terminalCount()const{return 2;}virtual bool branch(bool)const{return false;}
 virtual bool nonlinear()const{return false;}virtual bool dissipative()const{return false;}
 virtual double stepLimit(const std::vector<double>&,const std::vector<double>&)const{return 1;}
 virtual double current(double,const Stamp&,double)const=0;
 virtual double power(const Stamp&s,double i)const{return (s.now(positive())-s.now(negative()))*i;}
 virtual std::vector<double> terminalCurrents(const Stamp&,double i)const{return {i,-i};}
 virtual void readings(Json&,const Stamp&,double)const{}
};
class Resistor final:public Component{
public:using Component::Component;
 const char*type()const override{return "resistor";}bool dissipative()const override{return true;}
 void validate()const override{if(value()<1e-6||value()>1e12)throw std::runtime_error(label()+": resistance must be 1 micro-ohm to 1 tera-ohm.");}
 void stamp(Stamp&s)const override{s.conductance(positive(),negative(),1/value());}
 double current(double v,const Stamp&,double)const override{return v/value();}
};
class VoltageSource final:public Component{
public:using Component::Component;
 const char*type()const override{return "voltage";}void validate()const override{if(std::abs(value())>1e6)throw std::runtime_error("Voltage exceeds 1 MV.");}bool branch(bool)const override{return true;}
 void stamp(Stamp&s)const override{s.voltage(positive(),negative(),value());}double current(double,const Stamp&,double i)const override{return i;}
};
class CurrentSource final:public Component{
public:using Component::Component;
 const char*type()const override{return "current";}void validate()const override{if(std::abs(value())>1e6)throw std::runtime_error("Current exceeds 1 MA.");}
 void stamp(Stamp&s)const override{s.rhs(positive(),-value());s.rhs(negative(),value());}double current(double,const Stamp&,double)const override{return value();}
};
class Capacitor final:public Component{
public:using Component::Component;
 const char*type()const override{return "capacitor";}void validate()const override{if(value()<1e-12||value()>1)throw std::runtime_error(label()+": capacitance must be 1 pF to 1 F.");}bool branch(bool initial)const override{return initial;}
 void stamp(Stamp&s)const override{if(s.initial)s.voltage(positive(),negative(),0);else if(s.dt>0){double g=value()/s.dt,h=g*(s.old(positive())-s.old(negative()));s.conductance(positive(),negative(),g);s.rhs(positive(),h);s.rhs(negative(),-h);}}
 double current(double v,const Stamp&s,double i)const override{return s.initial?i:s.dt>0?value()/s.dt*(v-s.old(positive())+s.old(negative())):0;}
 void readings(Json&r,const Stamp&s,double)const override{double v=s.now(positive())-s.now(negative());r["energy"]=.5*value()*v*v;}
};
class Inductor final:public Component{
public:using Component::Component;
 const char*type()const override{return "inductor";}bool branch(bool)const override{return true;}
 void validate()const override{if(value()<1e-9||value()>1e6)throw std::runtime_error(label()+": inductance must be 1 nH to 1 MH.");}
 void stamp(Stamp&s)const override{
  if(s.initial){s.branchKcl(positive(),negative());s.add(s.branch,s.branch,1);return;}
  s.voltage(positive(),negative(),0);
  if(s.dt>0){double r=value()/s.dt;s.add(s.branch,s.branch,-r);s.rhs(s.branch,-r*s.oldCurrent(id()));}
 }
 double current(double,const Stamp&,double i)const override{return i;}
 void readings(Json&r,const Stamp&,double i)const override{r["energy"]=.5*value()*i*i;}
};
class Switch final:public Component{
 double resistance()const{return value()>.5?.001:1e12;}
public:using Component::Component;
 const char*type()const override{return "switch";}bool dissipative()const override{return true;}
 void validate()const override{if(value()!=0&&value()!=1)throw std::runtime_error("Switch state must be 0 (open) or 1 (closed).");}
 void stamp(Stamp&s)const override{s.conductance(positive(),negative(),1/resistance());}
 double current(double v,const Stamp&,double)const override{return v/resistance();}
 void readings(Json&r,const Stamp&,double)const override{r["state"]=value()>.5?"Closed":"Open";}
};
class Potentiometer final:public Component{
 double position_;
 double left()const{return std::max(1e-6,value()*position_);}
 double right()const{return std::max(1e-6,value()*(1-position_));}
public:
 Potentiometer(std::string id,std::string label,double v,double position):Component(std::move(id),std::move(label),v),position_(position){}
 const char*type()const override{return "potentiometer";}int terminalCount()const override{return 3;}bool dissipative()const override{return true;}
 void validate()const override{if(value()<1e-6||value()>1e12||!std::isfinite(position_)||position_<0||position_>1)throw std::runtime_error("Use positive resistance and a wiper position from 0 to 100%.");}
 void stamp(Stamp&s)const override{s.conductance(positive(),third(),1/left());s.conductance(third(),negative(),1/right());}
 double current(double,const Stamp&s,double)const override{return (s.now(positive())-s.now(third()))/left();}
 double power(const Stamp&s,double)const override{double a=s.now(positive())-s.now(third()),b=s.now(negative())-s.now(third());return a*a/left()+b*b/right();}
 std::vector<double> terminalCurrents(const Stamp&s,double)const override{double a=(s.now(positive())-s.now(third()))/left(),b=(s.now(negative())-s.now(third()))/right();return {a,b,-a-b};}
 void readings(Json&r,const Stamp&s,double)const override{r["wiperVoltage"]=s.now(third())-s.now(negative());r["setting"]=position_;}
};
class Diode final:public Component{
 std::string kind_;
 double vt()const{return kind_=="led"?.052:.02585;}
 JunctionValue evaluated(double v)const{
  double reference=kind_=="zener"?.7:value(),sat=.001/std::expm1(reference/vt());
  auto out=junctionValue(v,sat,vt());
  if(kind_=="zener"&&v < -value()){out.current+=(v+value())/10;out.g+=.1;}
  return out;
 }
public:
 Diode(std::string id,std::string label,double v,std::string kind):Component(std::move(id),std::move(label),v),kind_(std::move(kind)){}
 const char*type()const override{return kind_.c_str();}bool nonlinear()const override{return true;}bool dissipative()const override{return true;}
 void validate()const override{
  if(kind_=="zener"){if(value()<.5||value()>200)throw std::runtime_error("Zener breakdown must be 0.5 to 200 V.");}
  else if(kind_=="led"){if(value()<.8||value()>3.6)throw std::runtime_error("LED forward voltage must be 0.8 to 3.6 V.");}
  else if(value()<.15||value()>1.2)throw std::runtime_error("Diode forward voltage must be 0.15 to 1.2 V.");
 }
 void stamp(Stamp&s)const override{auto d=evaluated(s.now(positive())-s.now(negative()));s.junction(positive(),negative(),d.current,d.g);}
 double current(double v,const Stamp&,double)const override{return evaluated(v).current;}
 double stepLimit(const std::vector<double>&g,const std::vector<double>&x)const override{
  auto at=[](const std::vector<double>&v,int n){return n<0?0:v.at(n);};
  double delta=(at(x,positive())-at(x,negative()))-(at(g,positive())-at(g,negative()));
  return std::min(1.0,.18/std::max(1e-30,std::abs(delta)));
 }
 void readings(Json&r,const Stamp&s,double i)const override{
  double v=s.now(positive())-s.now(negative());
  r["state"]=kind_=="zener"&&v < -value()?"Breakdown":i>1e-6?"Conducting":"Off";
 }
};
class BipolarTransistor final:public Component{
 bool pnp_;
 struct Currents{double c,e,b,gf,gr,af,ar;};
 Currents evaluated(const Stamp&s)const{
  double sign=pnp_?-1:1,af=value()/(value()+1),ar=.5;
  auto forward=junctionValue(sign*(s.now(third())-s.now(negative())),1e-14/af,.02585);
  auto reverse=junctionValue(sign*(s.now(third())-s.now(positive())),1e-14/ar,.02585);
  double ic=sign*(af*forward.current-reverse.current),ie=sign*(-forward.current+ar*reverse.current);
  return {ic,ie,-ic-ie,forward.g,reverse.g,af,ar};
 }
public:
 BipolarTransistor(std::string id,std::string label,double beta,bool pnp):Component(std::move(id),std::move(label),beta),pnp_(pnp){}
 const char*type()const override{return pnp_?"pnp":"npn";}int terminalCount()const override{return 3;}
 bool nonlinear()const override{return true;}bool dissipative()const override{return true;}
 void validate()const override{if(value()<1||value()>1000)throw std::runtime_error("Transistor current gain must be 1 to 1000.");}
 void stamp(Stamp&s)const override{
  auto t=evaluated(s);int nodes[3]={positive(),negative(),third()};
  double currents[3]={t.c,t.e,t.b};
  double jac[3][3]={{t.gr,-t.af*t.gf,t.af*t.gf-t.gr},{-t.ar*t.gr,t.gf,-t.gf+t.ar*t.gr},{(t.ar-1)*t.gr,(t.af-1)*t.gf,(1-t.af)*t.gf+(1-t.ar)*t.gr}};
  for(int i=0;i<3;++i){double equivalent=-currents[i];for(int j=0;j<3;++j){s.add(nodes[i],nodes[j],jac[i][j]);equivalent+=jac[i][j]*s.now(nodes[j]);}s.rhs(nodes[i],equivalent);}
 }
 std::vector<double> terminalCurrents(const Stamp&s,double)const override{auto t=evaluated(s);return {t.c,t.e,t.b};}
 double current(double,const Stamp&s,double)const override{return evaluated(s).c;}
 double power(const Stamp&s,double i)const override{return (s.now(positive())-s.now(negative()))*i+(s.now(third())-s.now(negative()))*evaluated(s).b;}
 double stepLimit(const std::vector<double>&g,const std::vector<double>&x)const override{
  auto at=[](const std::vector<double>&v,int n){return n<0?0:v.at(n);};double maximum=0;
  for(int node:{positive(),negative()})maximum=std::max(maximum,std::abs((at(x,third())-at(x,node))-(at(g,third())-at(g,node))));
  return std::min(1.0,.15/std::max(1e-30,maximum));
 }
 void readings(Json&r,const Stamp&s,double)const override{
  auto t=evaluated(s);double sign=pnp_?-1:1,vbe=s.now(third())-s.now(negative()),vbc=s.now(third())-s.now(positive());
  r["baseCurrent"]=t.b;r["collectorCurrent"]=t.c;r["emitterCurrent"]=t.e;r["vbe"]=vbe;
  r["state"]=std::abs(t.c)<1e-8?"Cutoff":sign*vbc>.05?"Saturation":"Active";
 }
};
class Ground final:public Component{
public:using Component::Component;
 const char*type()const override{return "ground";}int terminalCount()const override{return 1;}
 void validate()const override{}void stamp(Stamp&)const override{}double current(double,const Stamp&,double)const override{return 0;}
};
// Circuit owns its components, nodes, and wires by composition.
class Circuit{
 std::vector<std::unique_ptr<Component>>components_;std::vector<Node>nodes_;std::vector<Wire>wires_;int netCount_=0;
public:
 const std::vector<Wire>&wires()const{return wires_;}

 explicit Circuit(const Json&project){
  if(project.at("schema").num()!=1)throw std::runtime_error("Unsupported schema.");
  auto&cs=project.at("components");auto&ws=project.at("wires");if(cs.kind!=Json::Array||ws.kind!=Json::Array)throw std::runtime_error("Expected component and wire arrays.");
  if(cs.array.size()>128||ws.array.size()>512)throw std::runtime_error("Limit: 128 components and 512 wires.");
  std::map<std::string,int>terminals;std::set<std::string>ids;std::vector<int>grounds;
  for(auto&j:cs.array){
   auto id=j.at("id").text(),type=j.at("type").text(),label=j.get("label").text(id);
   if(id.empty()||id.size()>64||!ids.insert(id).second)throw std::runtime_error("Invalid or duplicate component ID.");
   for(char c:id)if(!std::isalnum((unsigned char)c)&&c!='_'&&c!='-')throw std::runtime_error("Invalid ID.");
   if(j.at("value").kind!=Json::Number)throw std::runtime_error("Value must be numeric.");double v=j.at("value").num();std::unique_ptr<Component>c;
   if(type=="resistor")c.reset(new Resistor(id,label,v));
   else if(type=="voltage")c.reset(new VoltageSource(id,label,v));
   else if(type=="current")c.reset(new CurrentSource(id,label,v));
   else if(type=="capacitor")c.reset(new Capacitor(id,label,v));
   else if(type=="inductor")c.reset(new Inductor(id,label,v));
   else if(type=="switch")c.reset(new Switch(id,label,v));
   else if(type=="potentiometer"){if(j.get("setting").kind!=Json::Null&&j.get("setting").kind!=Json::Number)throw std::runtime_error("Wiper position must be numeric.");c.reset(new Potentiometer(id,label,v,j.get("setting").num(.5)));}
   else if(type=="diode"||type=="led"||type=="zener")c.reset(new Diode(id,label,v,type));
   else if(type=="npn"||type=="pnp")c.reset(new BipolarTransistor(id,label,v,type=="pnp"));
   else if(type=="ground")c.reset(new Ground(id,label,0));
   else throw std::runtime_error("Unsupported component: "+type);
   c->validate();for(int k=0;k<c->terminalCount();++k){std::string t=id+":"+std::to_string(k);terminals[t]=int(nodes_.size());if(type=="ground")grounds.push_back(int(nodes_.size()));nodes_.push_back({t,-1});}components_.push_back(std::move(c));
  }
  if(grounds.empty())throw std::runtime_error("Add a ground reference before running.");
  if(components_.size()==grounds.size())throw std::runtime_error("Add a source and components.");
  std::vector<int>parent(nodes_.size());for(size_t i=0;i<parent.size();++i)parent[i]=int(i);
  auto root=[&](int n){while(parent[n]!=n){parent[n]=parent[parent[n]];n=parent[n];}return n;};
  auto unite=[&](int a,int b){parent[root(a)]=root(b);};for(int g:grounds)unite(g,grounds[0]);
  for(auto&w:ws.array){auto a=w.at("from").text(),b=w.at("to").text();if(!terminals.count(a)||!terminals.count(b))throw std::runtime_error("Wire points to a missing terminal.");unite(terminals[a],terminals[b]);wires_.push_back({a,b});}
  int gr=root(grounds[0]);std::map<int,int>nets;
  for(size_t i=0;i<nodes_.size();++i){int r=root(int(i));if(r==gr)nodes_[i].net=-1;else{if(!nets.count(r))nets[r]=netCount_++;nodes_[i].net=nets[r];}}
  for(auto&c:components_){int p=nodes_[terminals[c->id()+":0"]].net,n=c->terminalCount()>1?nodes_[terminals[c->id()+":1"]].net:-1,third=c->terminalCount()>2?nodes_[terminals[c->id()+":2"]].net:-1;c->connect(p,n,third);if(std::string(c->type())=="voltage"&&p==n)throw std::runtime_error(c->label()+": source terminals are shorted.");}
 }
 const std::vector<std::unique_ptr<Component>>&components()const{return components_;}const std::vector<Node>&nodes()const{return nodes_;}int netCount()const{return netCount_;}
};
// Ideal-wire current is unique on graph bridges. Cyclic ideal-wire paths have
// no unique current split; expose null rather than inventing a distribution.
inline Json wireCurrents(const Circuit&c,const Json&rows){
 std::map<std::string,int>index;int count=int(c.nodes().size());
 for(int n=0;n<count;++n)index[c.nodes()[n].terminal]=n;
 std::vector<double>injection(count,0);std::vector<std::vector<std::pair<int,int>>>adj(count);
 for(const auto&r:rows.array){auto id=r.at("id").text();const auto&tc=r.at("terminalCurrents").array;for(size_t p=0;p<tc.size();++p)injection[index.at(id+":"+std::to_string(p))]=-tc[p].num();}
 std::vector<std::pair<int,int>>edges;
 auto add=[&](int a,int b){int edge=int(edges.size());edges.push_back({a,b});adj[a].push_back({b,edge});adj[b].push_back({a,edge});};
 for(const auto&w:c.wires())add(index.at(w.from),index.at(w.to));
 int ground=-1;for(const auto&part:c.components())if(std::string(part->type())=="ground"){int node=index.at(part->id()+":0");if(ground<0)ground=node;else add(ground,node);}
 std::vector<int>seen(count,-1),low(count);std::vector<double>flow(edges.size(),0);std::vector<bool>unique(edges.size(),false);int clock=0;
 std::function<double(int,int)>visit=[&](int node,int parent){
  seen[node]=low[node]=clock++;double total=injection[node];
  for(const auto&link:adj[node]){int next=link.first,edge=link.second;if(edge==parent)continue;
   if(seen[next]<0){double subtree=visit(next,edge);total+=subtree;low[node]=std::min(low[node],low[next]);if(low[next]>seen[node]){unique[edge]=true;flow[edge]=edges[edge].first==node?-subtree:subtree;}}
   else low[node]=std::min(low[node],seen[next]);
  }return total;
 };
 for(int n=0;n<count;++n)if(seen[n]<0)visit(n,-1);
 Json out=Json::arr();for(size_t n=0;n<c.wires().size();++n){const auto&w=c.wires()[n];Json row=Json::obj();row["index"]=int(n);row["from"]=w.from;row["to"]=w.to;row["determinate"]=unique[n]?true:false;row["current"]=unique[n]?Json(flow[n]):Json();out.push(row);}return out;
}
class SimulationEngine{
 static std::vector<double>gaussian(std::vector<std::vector<double>>a,std::vector<double>z){
  int n=int(z.size());for(int r=0;r<n;++r){double scale=0;for(double v:a[r])scale=std::max(scale,std::abs(v));if(scale==0)throw std::runtime_error("Floating node. Connect every network to ground.");for(double&v:a[r])v/=scale;z[r]/=scale;}
  for(int c=0;c<n;++c){int p=c;for(int r=c+1;r<n;++r)if(std::abs(a[r][c])>std::abs(a[p][c]))p=r;if(std::abs(a[p][c])<1e-13)throw std::runtime_error("Floating nodes, conflicting sources or redundant ideal-source loops.");std::swap(a[c],a[p]);std::swap(z[c],z[p]);for(int r=c+1;r<n;++r){double f=a[r][c]/a[c][c];for(int k=c;k<n;++k)a[r][k]-=f*a[c][k];z[r]-=f*z[c];}}
  std::vector<double>x(n);for(int r=n-1;r>=0;--r){double v=z[r];for(int k=r+1;k<n;++k)v-=a[r][k]*x[k];x[r]=v/a[r][r];if(!std::isfinite(x[r]))throw std::runtime_error("Numerical overflow.");}return x;
 }
public:
 Json solve(const Circuit&c,double dt=0,bool initial=false,const std::vector<double>&previous={},std::vector<double>*next=nullptr,const std::map<std::string,double>*history=nullptr)const{
  int size=c.netCount();bool nonlinear=false;std::map<std::string,int>branches;
  for(auto&v:c.components()){if(v->branch(initial))branches[v->id()]=size++;nonlinear=nonlinear||v->nonlinear();}
  std::vector<std::vector<double>>a(size,std::vector<double>(size));std::vector<double>z(size),guess(size),x;
  for(size_t i=0;i<previous.size()&&i<size_t(c.netCount());++i)guess[i]=previous[i];
  Stamp s{a,z,previous,dt,initial,-1,&guess,history};bool converged=false;int iterations=0;
  for(;iterations<(nonlinear?250:1);++iterations){
   for(auto&row:a)std::fill(row.begin(),row.end(),0);std::fill(z.begin(),z.end(),0);
   for(auto&v:c.components()){s.branch=branches.count(v->id())?branches[v->id()]:-1;v->stamp(s);}
   x=gaussian(a,z);if(!nonlinear){converged=true;break;}
   double limit=1,change=0;
   for(auto&v:c.components())limit=std::min(limit,v->stepLimit(guess,x));
   for(int i=0;i<size;++i){double tolerance=i<c.netCount()?1e-8+1e-7*std::max(std::abs(x[i]),std::abs(guess[i])):1e-10+1e-7*std::max(std::abs(x[i]),std::abs(guess[i]));change=std::max(change,std::abs(x[i]-guess[i])/tolerance);}
   if(change<=1&&limit>.99){converged=true;break;}
   for(int i=0;i<size;++i)guess[i]+=limit*(x[i]-guess[i]);
  }
  if(!converged)throw std::runtime_error("Nonlinear circuit did not converge. Check transistor pins and add current-limiting resistors.");
  s.estimate=&x;
  if(next)*next=std::vector<double>(x.begin(),x.begin()+c.netCount());
  auto voltage=[&](int n){return n<0?0:x.at(n);};Json out=Json::obj(),rows=Json::arr(),nodes=Json::obj(),nets=Json::arr();double loss=0,balance=0;
  for(auto&n:c.nodes())nodes[n.terminal]=voltage(n.net);
  for(int i=0;i<c.netCount();++i){Json n=Json::obj();n["name"]="N"+std::to_string(i+1);n["voltage"]=x[i];nets.push(n);}
  for(auto&v:c.components()){
   if(std::string(v->type())=="ground")continue;
   double dv=voltage(v->positive())-voltage(v->negative()),bc=branches.count(v->id())?x.at(branches[v->id()]):0,i=v->current(dv,s,bc),power=v->power(s,i);
   Json row=Json::obj();row["id"]=v->id();row["label"]=v->label();row["type"]=v->type();row["voltage"]=dv;row["current"]=i;row["power"]=power;Json currents=Json::arr();for(double current:v->terminalCurrents(s,i))currents.push(current);row["terminalCurrents"]=currents;v->readings(row,s,i);rows.push(row);balance+=power;if(v->dissipative())loss+=std::max(0.0,power);
  }
  out["components"]=rows;out["wires"]=wireCurrents(c,rows);out["nodeVoltages"]=nodes;out["nets"]=nets;out["dissipatedPower"]=loss;out["powerBalance"]=balance;out["iterations"]=iterations+1;return out;
 }
 Json transient(const Circuit&c,double duration,int steps)const{
  if(!std::isfinite(duration)||duration<=0||duration>3600||steps<2||steps>1000)throw std::runtime_error("Use 2-1000 steps and 0-3600 seconds.");
  bool reactive=false;for(auto&v:c.components())if(std::string(v->type())=="capacitor"||std::string(v->type())=="inductor")reactive=true;
  if(!reactive)throw std::runtime_error("Add a capacitor or inductor for transient analysis.");
  Json samples=Json::arr();std::vector<double>previous;std::map<std::string,double>history;
  auto remember=[&](const Json&frame){history.clear();for(auto&r:frame.at("components").array)history[r.at("id").text()]=r.at("current").num();};
  auto first=solve(c,0,true,{},&previous);first["time"]=0;samples.push(first);remember(first);double dt=duration/steps;
  for(int k=1;k<=steps;++k){std::vector<double>next;auto frame=solve(c,dt,false,previous,&next,&history);frame["time"]=k*dt;samples.push(frame);remember(frame);previous=std::move(next);}
  Json out=Json::obj();out["samples"]=samples;out["duration"]=duration;out["method"]="Backward Euler; zero initial capacitor voltages and inductor currents; DC sources step at t=0";return out;
 }
};
class ProjectManager{
 std::string directory_;
 std::string path(const std::string&id)const{if(id.empty()||id.size()>64)throw std::runtime_error("Invalid project ID.");for(char c:id)if(!std::isalnum((unsigned char)c)&&c!='_'&&c!='-')throw std::runtime_error("Invalid project ID.");return directory_+"/"+id+".sc.json";}
 static std::string readFile(const std::string&p){std::ifstream in(p,std::ios::binary);if(!in)throw std::runtime_error("Project could not be opened.");in.seekg(0,std::ios::end);auto n=in.tellg();if(n<0||n>2097152)throw std::runtime_error("Invalid file size.");in.seekg(0);std::ostringstream o;o<<in.rdbuf();if(in.bad())throw std::runtime_error("Read failed.");return o.str();}
 static void writeFile(const std::string&p,const std::string&s){std::ofstream out(p,std::ios::binary|std::ios::trunc);if(!out)throw std::runtime_error("Project folder is not writable.");out<<s;out.flush();if(!out)throw std::runtime_error("Save failed.");}
public:
 explicit ProjectManager(std::string d):directory_(std::move(d)){if(directory_.empty())throw std::runtime_error("Project folder not configured.");}
 Json list()const{std::ifstream in(directory_+"/index.json");if(!in)return Json::arr();std::ostringstream o;o<<in.rdbuf();auto j=Json::parse(o.str());if(j.kind!=Json::Array)throw std::runtime_error("Invalid project index.");return j;}
 void save(const Json&p)const{if(p.at("schema").num()!=1||p.at("components").kind!=Json::Array||p.at("wires").kind!=Json::Array)throw std::runtime_error("Invalid project.");auto id=p.at("id").text();auto target=path(id);auto data=p.dump();if(data.size()>2097152)throw std::runtime_error("Project exceeds 2 MB.");writeFile(target,data);auto old=list(),rows=Json::arr();for(auto&r:old.array)if(r.get("id").text()!=id)rows.push(r);Json row=Json::obj();row["id"]=id;row["title"]=p.get("title").text("Untitled circuit");rows.push(row);writeFile(directory_+"/index.json",rows.dump());}
 Json load(const std::string&id)const{return Json::parse(readFile(path(id)));}
 // Recovery is separate from the named-project index and accepts unfinished circuits.
 void checkpoint(const Json&project,bool dirty)const{
  path(project.at("id").text());
  if(project.at("schema").num()!=1||project.at("title").kind!=Json::String||project.at("components").kind!=Json::Array||project.at("wires").kind!=Json::Array)throw std::runtime_error("Invalid recovery project.");
  Json state=Json::obj();state["project"]=project;state["dirty"]=dirty;
  auto data=state.dump();if(data.size()>2097152)throw std::runtime_error("Workspace exceeds 2 MB.");
  writeFile(directory_+"/workspace.json",data);
 }
 Json restore()const{
  auto filename=directory_+"/workspace.json";std::ifstream in(filename,std::ios::binary);
  if(!in)return Json();in.close();auto state=Json::parse(readFile(filename));
  const auto&p=state.at("project");path(p.at("id").text());
  if(p.at("schema").num()!=1||p.at("title").kind!=Json::String||p.at("components").kind!=Json::Array||p.at("wires").kind!=Json::Array||p.at("components").array.size()>128||p.at("wires").array.size()>512)throw std::runtime_error("Invalid saved workspace.");
  return state;
 }
};
inline Json execute(const Json&r){
 auto op=r.at("op").text();Json out=Json::obj();out["ok"]=true;
 if(op=="simulate"||op=="validate"||op=="transient"){Circuit c(r.at("project"));SimulationEngine e;if(op=="simulate")out["result"]=e.solve(c);else if(op=="transient"){double steps=r.get("steps").num(200);if(steps<2||steps>1000||std::floor(steps)!=steps)throw std::runtime_error("Use 2-1000 integer steps.");out["result"]=e.transient(c,r.get("duration").num(.05),int(steps));}else{out["netCount"]=c.netCount();out["message"]="Topology validated; run to check solvability.";}}
 else if(op=="save"||op=="load"||op=="list"){ProjectManager p(r.at("directory").text());if(op=="save"){p.save(r.at("project"));out["message"]="Project saved";}else if(op=="load")out["project"]=p.load(r.at("id").text());else out["projects"]=p.list();}
 else if(op=="checkpoint"||op=="restore"){
  ProjectManager p(r.at("directory").text());
  if(op=="checkpoint")p.checkpoint(r.at("project"),r.get("dirty").boolean);
  else{auto state=p.restore();out["project"]=state.kind==Json::Null?Json():state.at("project");out["dirty"]=state.kind==Json::Null?Json(false):state.get("dirty");}
 }
 else throw std::runtime_error("Unknown operation.");return out;
}
}

