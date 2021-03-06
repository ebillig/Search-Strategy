setwd("~/Search_Strategy")
#set seed
seednumber=1
set.seed(seednumber)

#load libraries
library("lubridate")
library("PBSmapping")
library("plyr")
library("inline")
library("Rcpp")
library("foreach")

##set up timer
tic <- function(gcFirst = TRUE, type=c("elapsed", "user.self", "sys.self"))
{
  type <- match.arg(type)
  assign(".type", type, envir=baseenv())
  if(gcFirst) gc(FALSE)
  tic <- proc.time()[type]         
  assign(".tic", tic, envir=baseenv())
}

toc <- function()
{
  type <- get(".type", envir=baseenv())
  toc <- proc.time()[type]
  tic <- get(".tic", envir=baseenv())
  toc - tic
}

###########################
###read data##############
#############################

tic()

runsimulation <- function(truebeta,trueRb){

  totalnuminf=1
  indicator=indicator2=0
  while(sum(indicator)<6){
    
    
    #locations uniform on [0,1]x[0,1] grid
    data <- read.csv("sim_map.csv")
    data$uniblock <- as.numeric(data$uniblock)
    blocks <- data$uniblock

    #look at blocks
    plot(data$X, data$Y, col=data$uniblock,pch=16)

    #number of houses in simulation
    N <- dim(data)[1]
    
    #create ids
    id<-c(1:N) #simulate 100 houses
    
    #calculate distances between houses
    distance<-matrix(NA,nrow=N,ncol=N)
    for (i in 1:N){
      for (j in 1:N){
        distance[i,j]=sqrt((data$X[i]-data$X[j])^2+(data$Y[i]-data$Y[j])^2)
      }
    }
    
    #simulate epidemic
    beta=truebeta
    Rb=trueRb
    K=1000 #carrying capacity
    maxt=40
    tobs=39
    
    beverton.holt<-function(id,K,R,bugs,trueremovaltime,trueinfectiontime){
      for(t in trueinfectiontime:(trueremovaltime-1)){
        bugs[id,(t+1)]=ceiling(R*bugs[id,t]/(1+bugs[id,t]/(K/(R-1))))
      }
      return(bugs[id,])
    }
    
    S=I=R=matrix(NA, nrow=N,ncol=N*N) 
    bugs=bugs.Rb=matrix(0,nrow=N,ncol=maxt)
    
    #probability of infestation differs by hops (<.3) or jumps (>.3)
    lambda <- 0.3
    delta <- 9
    
    thresholdblocks<-matrix(0,nrow=N,ncol=N)
    for(i in 1:N){
      for(j in 1:N){
        thresholdblocks[i,j] <- ifelse(data$uniblock[i]==data$uniblock[j], 1 , lambda)
      }
    }
    
    threshold<-matrix(0,nrow=N,ncol=N)
    for(i in 1:N){
      for(j in 1:N){
        threshold[i,j] <- thresholdblocks[i,j]*exp(-distance[i,j]/delta)
      }
    }
    
    #initial state vectors
    S[,1]<-rep(1,N)
    I[,1]<-rep(0,N)
    R[,1]<-rep(0,N)
    
    #initial infective
    initialinfective<-sample(1:N,1)
    S[initialinfective,1]=0
    I[initialinfective,1]=1
    
    
    #keeping counts of S, E, and I at all the time points of the simulation
    StoI=ItoR=rep(0,N)
    infectiontime=rep(0,N)
    removaltime=rep(0,N)
    
    #probability that i infects j
    h1<-function(t,r,I,i,j,beta){
      n=1
      deriv <- r^(t-I[i])*log(r)-(K-1)*K*r^(t-I[i])*log(r)/(K+r^(t-I[i])-1)^2
      hazard=ifelse(deriv>0,1-(1-beta/N*threshold[i,j])^(deriv),0)
      return(hazard) 
    }
    
    #find initial infectives notification and recovery times
    infectiontime[initialinfective]<-1
    bugs[initialinfective,1]<-1
    removaltime[initialinfective]<-maxt
    bugs[initialinfective,]=rpois(maxt,beverton.holt(initialinfective,K,Rb,bugs,maxt,infectiontime[initialinfective]))
    bugs[initialinfective,]=ifelse(bugs[initialinfective,]==0,1,bugs[initialinfective,])
    bug.ind=matrix(NA,nrow=N,ncol=N)
    for(t in 2:(maxt-1)){   #looping through each day of the simulation
      for(i in 1:N){
        for(j in 1:N){
          bug.ind[i,j]=1-ifelse(t>=infectiontime[i]&infectiontime[i]>0,h1(t,Rb,infectiontime,i,j,beta),0)
        }}
      for(j in 1:N){
        ifelse(S[j,(t-1)]==1, StoI[j]<-rbinom(1,S[j,(t-1)],1-prod(bug.ind[,j])),StoI[j]<-0)
        if(StoI[j]==1){
          infectiontime[j]<-t
          bugs[j,t]=1
          removaltime[j]<-maxt
          bugstemp=beverton.holt(j,K,Rb,bugs,maxt,infectiontime[j])
          bugs[j,(t:maxt)]=rpois((maxt-t+1),bugstemp[t:maxt])
        }
      } 
      
      #Now update the daily counts
      S[,t]=S[,(t-1)]-StoI
      I[,t]=I[,(t-1)]+StoI-ItoR
      R[,t]=R[,(t-1)]
    }  
    
    
    S=S[,1:(maxt-1)]
    I=I[,1:(maxt-1)]
    R=R[,1:(maxt-1)]
    
    
    #look at distribution at a few times
    par(mfrow=c(2,2))
    t=1
    plot(data$X,data$Y,col="gray",main = substitute(paste(Time, " = ", t),list(t=t)),xlab="X",ylab="Y")
    for (i in 1:N) if(I[i,t]==1) points(data$X[i],data$Y[i],pch=19,col="red")
    t=round(maxt/4)
    plot(data$X,data$Y,col="gray",xlab="X",ylab="Y",main = substitute(paste(Time, " = ", t),list(t=t)))
    for (i in 1:N) if(I[i,t]==1) points(data$X[i],data$Y[i],pch=19,col="red")
    t=round(maxt/2)
    plot(data$X,data$Y,col="gray",xlab="X",ylab="Y",main = substitute(paste(Time, " = ", t),list(t=t)))
    for (i in 1:N) if(I[i,t]==1) points(data$X[i],data$Y[i],pch=19,col="red")
    t=maxt-1
    plot(data$X,data$Y,col="gray",xlab="X",ylab="Y",main = substitute(paste(Time, " = ", t),list(t=t)))
    for (i in 1:N) if(I[i,t]==1) points(data$X[i],data$Y[i],pch=19,col="red",xlab="X",ylab="Y",main = substitute(paste(Time, " = ", t),list(t=t)))
    
    
    #count total number infected
    totalnuminf=sum(S[,1])-sum(S[,maxt-1])
    
    check3=ifelse(infectiontime<=tobs&infectiontime!=0,bugs[,tobs], Inf)
    indicator=length(check3[which(check3>0&check3<Inf)])
    indicator2=length(infectiontime[which(infectiontime>tobs)])
  }
  #make dataset
  data=cbind(infectiontime, removaltime,bugs)
  truebugs=bugs
  
  #delete a few observations
  #update data to reflect only OBSERVED data
  temp<-which(infectiontime!=0&infectiontime!=1)
  delete.number=floor(1/3*length(temp))
  occults <-sample(temp,delete.number)
  infectiontime[occults]<-0
  bugs[occults,]=0
  predprobs <- rep((totalnuminf+1)/(N),N)
  
  return(list(data,occults,bugs,predprobs, threshold, blocks, distance))
}

  
runMCMC <- function(betastart, Rbstart, totaliterations,data, occults, bugs, predprobs, truebeta, trueRb, threshold, N, blocks, distance){

########################################################
#########MCMC algorithm###################################
#######################################################

##Jewell MCMC
M <- totaliterations #length of simulation
m <- 1 #first iteration
maxt <- 40
infectiontime <- data[,1]
removaltime <- data[,2]
totalnuminf=1

tobs <- rep(maxt,N)

#define number of houses
occult.sum.new<-rep(0,N)
inspected <- rep(0,N)
sum.insp.temp <- bugs[,maxt-1]

#determine random observation times
for (i in 1:length(sum.insp.temp)){
  if(sum.insp.temp[i]>0){
    tobs[i] <- round(runif(1,min = infectiontime[i], max = maxt-1))
    inspected[i]=1
  }
}

sum.insp <- rep(0,N)
for(i in 1:N) sum.insp[i] <- bugs[i,tobs[i]]

infectiontime<-rep(Inf,N)
check3<- rep(Inf,N) #initialize data vector
T_b <- 0.2 #threshold for bug infectiousness
jumpprob <- .02 #probability of jump vs. hop
bugs <- matrix(0,nrow=N,ncol=maxt) #initialize but matrix
maxbugs <- max(sum.insp) #find most observed bugs in data
initialinfective <- which(data[,1]==1) #set this house as initialinfective
id=1:N #generate ids
K=1000 #carrying capacity
tuning <- 0.01 #tuning parameter for RJ
lambda <- 0.3
delta <- 9


check3<-ifelse(sum.insp>0,sum.insp,Inf) #replace with observed bug counts
I=ifelse(check3!=Inf&check3!=Inf,10,Inf) #set initial values for infection times

trueremovaltime=ifelse(check3<Inf,maxt+1,Inf) #set recovery times 
detectiontime=ifelse(check3>0&check3<Inf,tobs,Inf) #set detection time vector

#initialize parameters 
beta=Rb=rep(0,M)
beta[1]=betastart
betastar=.2
Rb[1]=Rbstart
betastar.I=matrix(0,nrow=N,ncol=N)
betastar.sum=rep(0,N)
S=H.mat=matrix(0,nrow=N,ncol=N)
U=rep(0,N)
accept.beta <- rep(0,M)
accept.Rb <- rep(0,M)
accept.I <- rep(0,M)
thresholdsum <- apply(threshold,1,sum)
threshold<-matrix(0,nrow=N,ncol=N)

#keep track of occult infestations
occult <- rep(0,N)

#initialize infection times
I[initialinfective]=1
Istar=I

#define indicators for infected houses
N_N=which(check3!=Inf)
N_I=which(I!=Inf)
#take out initial infective
N_N=N_N[which(N_N!=initialinfective)]
N_I=N_I[which(N_I!=initialinfective)]
infectedhouses=rep(0,N)
infectedhouses[N_N]=1
infectedhousesI=rep(0,N)
infectedhousesI[N_I]=1

#intialize bug mean vector
lambda_t=rep(0,N)
lambda_t[1]=1

#keep track of rankings
rankings1 <- rankings2 <- matrix(0,nrow=N,ncol=M/100)

############################################
###############functions####################


`%notin%` <- function(x,y) !(x %in% y) 

sampleWithoutSurprises <- function(x) {
  if (length(x) <= 1) {
    return(x)
  } else {
    return(sample(x,1))
  }
}

thresholdblocks<-matrix(0,nrow=N,ncol=N)
for(i in 1:N){
  for(j in 1:N){
    thresholdblocks[i,j] <- ifelse(blocks[i]==blocks[j], 1 , lambda)
  }
}


#BH function to update bug counts given matrix
beverton.holt<-function(id,K,R,bugs,maxt,trueinfectiontime){
  for(t in trueinfectiontime:(maxt-1)){
    bugs[id,(t+1)]=ceiling(R*bugs[id,t]/(1+bugs[id,t]/(K/(R-1))))
  }
  return(bugs[id,])
}

#BH function to update infection times
beverton.holt.I<-function(update,K,R,check3,tobs,bugs){
  tobs1=tobs
  time=ifelse(update %in% N_N, -log((K-check3[update])/(check3[update]*K-check3[update]))/log(R),-log((K-bugs[update,tobs1])/(bugs[update,tobs1]*K-bugs[update,tobs1]))/log(R))
  I[update]=tobs1-time
  return(I[update])
}


#BH function to udpate bug counts given vector
beverton.holt.update<-function(K,R,bugs,trueremovaltime,trueinfectiontime){
  for(t in trueinfectiontime:(min(maxt-1,trueremovaltime))){
    bugs[(t+1)]=ceiling(R*bugs[t]/(1+bugs[t]/(K/(R-1))))
  }
  return(bugs)
}


#poisson piece of likelihood for matrix
f_D<-function(i,bugs,I,check3,Rb){
  den=0
  lambda_t=beverton.holt.update(K,Rb,lambda_t,maxt,1)
  if(check3[i]<Inf){
    adjusted.bugs=bugs[i,which(bugs[i,]!=0)]
    den=den+dpois(adjusted.bugs,lambda_t[1:length(adjusted.bugs)],log=TRUE)
  }
  
  return(den)
}

#poisson piece of likelihood for vector
f_D.update<-function(i,bugs,I,check3,Rb){
  den=0
  lambda_t=beverton.holt.update(K,Rb,lambda_t,maxt,1)
  if(check3[i]<Inf){
    adjusted.bugs=bugsstar[which(bugsstar!=0)]
    den=den+dpois(adjusted.bugs,lambda_t[1:length(adjusted.bugs)],log=TRUE)
  }
  
  return(den)
}


#' First piece of likelihood
#'
#' @param I Numeric vector of times.
#' @param beta Float hazard rate for infection.
#' @param initialinfective Cardinal of initial infected house.
#' @param r Growth rate, a float.
#' @param K Distance factor?, a float.
#' @param N Number of houses.
#' @param N_I Those houses that were surveiled? A list of indices.
#' @param threshold NxN matrix of float cutoff distances.
#' @return Array of likelihoods, as numeric vector.

firstpiece <- function(I, beta, initialinfective, r, K, N, N_I, threshold) {
  H.mat <- matrix(1, nrow=N, ncol=N)
  beta.sum <- rep(1, N)
  for (j in 1:N) {
    for (i in 1:N) {
      if (i %in% N_I | i==initialinfective) {
        if (I[i]<I[j] & I[j]<Inf) {
          t<-I[j]-I[i]
          deriv <- r^t*log(r)-(K-1)*K*r^t*log(r)/(K+r^t-1)^2
          H.mat[i,j] <- ifelse(deriv>0, (1-beta*threshold[i,j])^(deriv), 1)
        }
      }
    }
    beta.sum[j] <- 1- prod(H.mat[,j])
  }
  ifelse(is.na(beta.sum), 0, beta.sum)
}

first.include <- '
#include <set>
#include <cmath>
'

firstpiece.wrap <- cxxfunction(signature(IS="numeric", betaS="float",initialinfectiveS="int", rS="float", KS="float", NS="int", N_IS="numeric",thresholdS="numeric"), plugin="Rcpp", incl=first.include, body='
                               Rcpp::NumericVector I(IS);
                               double beta=Rcpp::as<double>(betaS);
                               int initialinfective=Rcpp::as<int>(initialinfectiveS);
                               double r=Rcpp::as<double>(rS);
                               double K=Rcpp::as<double>(KS);
                               int N=Rcpp::as<int>(NS);
                               Rcpp::NumericVector N_I(N_IS);
                               Rcpp::NumericVector threshold(thresholdS);
                               std::set<int> infecteds(N_I.begin(), N_I.end());
                               typedef std::set<int>::const_iterator infiter;
                               infecteds.insert(initialinfective);
                               Rcpp::NumericVector H(N, 1.0);
                               for (int j=0; j<N; ++j) {
                               double total=1;
                               for (infiter it=infecteds.begin(); it!=infecteds.end(); ++it) {
                               int i=*it - 1; // -1 to convert to 0-based indexing.
                               if (I[i]<I[j] && std::isfinite(I[j])) {
                               double deriv=std::pow(r,(I[j]-I[i]))*std::log(r)-(K-1)*K*std::pow(r,(I[j]-I[i]))*std::log(r)/std::pow((K+std::pow(r,(I[j]-I[i]))-1),2);
                               if (deriv>0) {
                               double add=std::pow(1-beta*threshold[i*N+j], deriv);
                               //std::cout << "i "<<i<<" j " << j<<" I i "<<I[i]<<" I[j] "<< I[j]
                               //<<" deriv " << deriv << " hmat " << add <<std::endl;
                               total*=add;
                               }
                               }
                               }
                               H[j]=1-total;
                               }
                               return H;
                               ')

H <- function(i, j, t, r, I, beta, K, threshold) {
  h <- rep(0,t)
  for(a in 1:t){
    deriv <- r^a*log(r)-(K-1)*K*r^a*log(r)/(K+r^a-1)^2
    h[a] <- ifelse(deriv>0, 1-(1-beta*threshold[i,j])^(deriv), 0)
  }
  sum(h)
}

secondpiece <- function(I, trueremovaltime, beta, r, K, N, maxt, threshold) {
  S1 <- matrix(0, nrow=N, ncol=N)
  for (i in 1:N) {
    if (I[i]!=Inf) {
      for (j in 1:N) {
        t <- min(maxt, I[j],trueremovaltime[i]) - min(I[i], I[j])
        if (t>0) {
          S1[i,j] <- H(i, j, t, r, I, beta, K, threshold)
        }
      }
    }
  }
  S1<-ifelse(S1=="NaN", 0, S1)  
  sum(S1)
}


#' Second piece of likelihood
#'
#' @param I Numeric vector of times.
#' @param beta Float hazard rate for infection.
#' @param r Growth rate, a float.
#' @param K Distance factor?, a float.
#' @param N Number of houses.
#' @param maxt A maximum time, a float.
#' @param threshold NxN matrix of float cutoff distances.
#' @return Single sum, a float.

secondpiece.wrap <- function(I, beta, r, K, N, maxt, threshold,thresholdsum) {
  S1 <- matrix(0, nrow=N, ncol=N)
  for (i in 1:N) {
    if (I[i]!=Inf) {
      for (j in 1:N) {
        t <- min(maxt, I[j]) - min(I[i], I[j])
        if (t>0) {
          S1[i,j] <- H(i, j, t, r, I, beta, K, threshold)
        }
      }
    }
  }
  S1<-ifelse(S1=="NaN", 0, S1)  
  sum(S1)/N
}

secondpiece.wrap <- cxxfunction(signature(IS="numeric", trueremovaltimeS="numeric",betaS="float",rS="float", KS="float", NS="int", maxtS="float",thresholdS="numeric",thresholdsumS="numeric"), plugin="Rcpp", incl=first.include, body='
                                Rcpp::NumericVector I(IS);
                                Rcpp::NumericVector trueremovaltime(trueremovaltimeS);
                                double beta=Rcpp::as<double>(betaS);
                                double r=Rcpp::as<double>(rS);
                                double K=Rcpp::as<double>(KS);
                                int N=Rcpp::as<int>(NS);
                                double maxt=Rcpp::as<double>(maxtS);
                                Rcpp::NumericVector threshold(thresholdS);
                                Rcpp::NumericVector thresholdsum(thresholdsumS);
                                
                                double total=0;
                                double add=0;
                                for (int i=0; i<N; ++i) {
                                if (std::isfinite(I[i])) {
                                for (int j=0; j<N; ++j) {
                                double t=std::min(std::min(trueremovaltime[i],maxt), I[j]) - std::min(I[i], I[j]);
                                if (t>0) {
                                for (int a=1; a<=t;++a){
                                double deriv=std::pow(r,a)*std::log(r)-(K-1)*K*std::pow(r,a)*std::log(r)/std::pow((K+std::pow(r,a)-1),2);
                                double result=1-std::pow(1-beta*threshold[i*N+j], deriv);
                                add+= result/N;
                                if (std::isfinite(add)) {
                                total+=add;
                                }
                                }
                                }
                                }
                                }
                                }
                                return Rcpp::wrap(add);
                                ')

##############################
#########for loop begins#######
##############################
bugsize=NULL
infectiontime=I
id = 1:N

#find initial infectives notification and recovery times
infectiontime[initialinfective]<-1
bugs[initialinfective,1]<-1
bugs[initialinfective,]=rpois(maxt,beverton.holt(initialinfective,K,Rb[1],bugs,maxt,infectiontime[initialinfective]))

#initialize bug counts
for (i in which(I!=Inf)){
  bugs[i,I[i]]=1
  bugstemp=beverton.holt(i,K[1],Rb[1],bugs,maxt,I[i])
  bugs[i,(I[i]:min(trueremovaltime[i],maxt))]=rpois((min(maxt,trueremovaltime[i])-I[i]+1),bugstemp[I[i]:min(maxt,trueremovaltime[i])])
  bugs[i,tobs[i]]=ifelse(check3[i]<Inf,check3[i],bugs[i,tobs[i]])
}

for (m in 2:M){
  
  ##################################
  ####update spatial parameters#####
  ##################################
  
  #draw lambda
  lambda <- abs(rnorm(1, 0.3, 0.09))
  delta <- rnorm(1, 9, 0.9)
  

  thresholdblocks<- ifelse(thresholdblocks==1, 1 , lambda)

  threshold <- thresholdblocks*exp(-distance/delta)

  ################################
  ######update Rb##################
  ####################################
  
  Rbstar=rnorm(1,Rb[m-1],.02)
  if(Rbstar<1) Rbstar=1+(1-Rbstar)
  Q=Qstar=rep(NA,length(I[which(I!=Inf)]))
  
  for (i in which(I!=Inf)){
    Qstar[which(I!=Inf)==i]=f_D(i,bugs,Istar,check3,Rbstar)[length(f_D(i,bugs,Istar,check3,Rbstar))]
    Q[which(I!=Inf)==i]=f_D(i,bugs,I,check3,Rb[m-1])[length(f_D(i,bugs,I,check3,Rb[m-1]))]
  }
  thirdpieceloglike <- sum(Qstar[which(Qstar!="NA")])-sum(Q[which(Q!="NA")])
  
  logfirstpieceIstar <- log(firstpiece.wrap(Istar, beta[m-1], initialinfective, Rbstar, K, N, N_I, threshold))
  logfirstpieceIstar <- ifelse(logfirstpieceIstar=="-Inf",0,logfirstpieceIstar)
  loglikestar <- sum(logfirstpieceIstar)-secondpiece.wrap(I, trueremovaltime,beta[m-1], Rbstar, K, N, maxt, threshold,thresholdsum)
  
  logfirstpiece<-log(firstpiece.wrap(I, beta[m-1], initialinfective, Rb[m-1], K, N, N_I, threshold))
  logfirstpiece <- ifelse(logfirstpiece=="-Inf",0,logfirstpiece)
  loglike<- sum(logfirstpiece)-secondpiece.wrap(I, trueremovaltime,beta[m-1], Rb[m-1], K, N, maxt, threshold,thresholdsum)
  
  priors <- dgamma(Rbstar,shape=trueRb*100,scale=1/100,log=TRUE)-dgamma(Rb[m-1],shape=trueRb*100,scale=1/100,log=TRUE)
  
  Rbloglike <- loglikestar+thirdpieceloglike-loglike+priors
  #Metropolis step
  mstep.Rb=min(0,Rbloglike)
  #if(mstep.Rb=="NaN") mstep.Rb=0
  R=log(runif(1))
  if(R<mstep.Rb){
    Rb[m]=Rbstar
    loglike<-loglikestar
    Q<-Qstar
    accept.Rb[m] <- 1
  }else{
    Rb[m]=Rb[m-1]
    accept.Rb[m] <- 0}
  
  ###############
  ##update beta##
  ###############
  #a.beta <- 100*beta[m-1]
  #b.beta <- 100-beta[m-1]*100
  betastar=abs(rnorm(1 , beta[m-1] , .1))
  if(betastar>1) betastar <- abs(1-betastar)
  logfirstpiecestar<-log(firstpiece.wrap(I, betastar, initialinfective, Rb[m], K, N, N_I, threshold))
  logfirstpiecestar=ifelse(logfirstpiecestar=="-Inf",0,logfirstpiecestar)
  loglikestar=sum(logfirstpiecestar)-secondpiece.wrap(I, trueremovaltime, betastar, Rb[m], K, N, maxt, threshold,thresholdsum)
  betapriors <- dbeta(betastar,shape1=truebeta*10,shape2=10-truebeta*10,log=TRUE)-dbeta(beta[m-1],shape1=truebeta*10,shape2=10-truebeta*10,log=TRUE)
  mstep.beta=min(1,exp(loglikestar-loglike+betapriors))
  if(mstep.beta=="NaN") mstep.beta=1
  R=runif(1)
  if(R<mstep.beta){
    beta[m]=betastar
    loglike <- loglikestar
    accept.beta[m]=1
  }else{
    beta[m]=beta[m-1]
    accept.beta[m]=0
  }
  
  
  ########################################################
  #####decide whether to update I, add I, or delete I#####
  ########################################################
  add.del.move<-sample(c("add","del","move"),1)
  
  if(add.del.move=="move"){
  ############
  ##update I##
  ############
  accept.I[m] <- 0
  ##pick a house to update the time out infected houses
  update=sample(N_I,1,replace=TRUE)
  if(bugs[update,min(maxt,trueremovaltime[update])]==0) bugs[update,min(maxt,trueremovaltime[update])]=1
  Istar[update] <- sample(c(2:(maxt-2)),1,replace=TRUE)
  bugsstar=rep(0,maxt)
  bugsstar[Istar[update]]=1
  bugsstar=beverton.holt.update(K,Rb[m],bugsstar,maxt,Istar[update])
  bugsstar[tobs[update]]=check3[update]
  logfirstpieceI<-log(firstpiece.wrap(I, beta[m], initialinfective, Rb[m], K, N, N_I, threshold))
  logfirstpieceI=ifelse(logfirstpieceI=="-Inf",0,logfirstpieceI)
  loglike=sum(logfirstpieceI)-secondpiece.wrap(I, trueremovaltime,beta[m], Rb[m], K, N, maxt, threshold,thresholdsum)
  logfirstpieceIstar<-log(firstpiece.wrap(Istar, beta[m], initialinfective, Rb[m], K, N, N_I, threshold))
  logfirstpieceIstar=ifelse(logfirstpieceIstar=="-Inf",0,logfirstpieceIstar)
  loglikestar=sum(logfirstpieceIstar)-secondpiece.wrap(Istar, trueremovaltime,beta[m], Rb[m], K, N, maxt, threshold,thresholdsum)
  Q=sum(f_D.update(update,bugsstar,Istar,check3,Rb[m]))-sum(f_D(update,bugs,I,check3,Rb[m]))
  
  #Metroplis step; decide whether to accept new time#
  mstep.I=min(1,exp(loglikestar-loglike+Q))
  if(mstep.I=="NaN") mstep.I=1
  
  R=runif(1)
  if(R<mstep.I){
    I<-Istar
    bugs[update,]=bugsstar
    loglike<-loglikestar
    accept.I[m] <- 1
  }else{
    Istar<-I
  } 
  
  }else if(add.del.move=="add"){ 
    
    ###########
    ###add I###
    ##########
    accept.I[m] <- 3
    addinf<-which(I==Inf)
    if(length(addinf)>1){
      update=sample(addinf,1)
      Istar[update]=floor(runif(1,min=2,max=maxt-2))
      trueremovaltime[update]=Inf
      detectiontime[update]=maxt
      tobs[update]=maxt
      bugsstar=rep(0,maxt)
      bugsstar[Istar[update]]=1
      N_Istar <- c(N_I, update)
      lambda.bugsstar <- beverton.holt.update(K,Rb[m],bugsstar,trueremovaltime[update],Istar[update])[(Istar[update]):maxt]
      bugsstar<-rpois((min(maxt,trueremovaltime[update])-Istar[update]+1),lambda.bugsstar)
      bugsstar <- ifelse(bugsstar==0, 1, bugsstar)
      bugstest=bugs
      bugstest[update,(Istar[update]:maxt)] <- bugsstar
      bugprior <- prod(dgamma(bugsstar, lambda.bugsstar, 1))
      check3[update]<-ifelse(inspected[update]==1,0,bugsstar[tobs[update]-Istar[update]+1])
      check3[update]<-ifelse(check3[update]>K,K,check3[update])
      logfirstpieceI<-log(firstpiece.wrap(I, beta[m], initialinfective, Rb[m], K, N, N_I, threshold))
      logfirstpieceI <- ifelse(logfirstpieceI=="-Inf",0,logfirstpieceI)
      loglike <- sum(logfirstpieceI)-secondpiece.wrap(I, trueremovaltime, beta[m], Rb[m], K, N, maxt, threshold,thresholdsum)
      logfirstpieceIstar <- log(firstpiece.wrap(Istar, beta[m], initialinfective, Rb[m], K, N, N_Istar, threshold))
      logfirstpieceIstar <- ifelse(logfirstpieceIstar=="-Inf",0,logfirstpieceIstar)
      loglikestar <- sum(logfirstpieceIstar)-secondpiece.wrap(Istar, trueremovaltime, beta[m], Rb[m], K, N, maxt, threshold,thresholdsum)
      
      alpha.p <- 10*predprobs[update]
      beta.p <- 10-alpha.p
      alpha.n <- 10*(totalnuminf+1)/N
      beta.n <- 10 - alpha.n
      probifadded <- (sum(occult[update])+1)/m
      probifnotadded <- sum(occult[update])/m
      if(probifnotadded==0) probifnotadded <- 0.1/m
      extra.piece=(length(addinf))/(length(N_I)-length(N_N)+1)*dunif(update,min=1,max=length(which(I==Inf)))*dbeta(probifadded, alpha.p, beta.p) 
      
      #metropolis hastings step for adding an infection
      mstep.I=min(1,exp(loglikestar-loglike)*extra.piece)
      if(mstep.I=="NaN") mstep.I=1
      R=runif(1)
      if(R<mstep.I){
        I<-Istar
        N_I<-c(N_I,update)
        infectedhousesI[N_I]=1
        bugs[update,]=bugstest[update,]
        loglike <-loglikestar
        Q<-Qstar
        accept.I[m] <- 2
      }else{
        Istar<-I
        trueremovaltime[update]=tobs[update]=Inf
        detectiontime[update] <- Inf
        check3[update]<-Inf}
    }
  }else{
    
    ###############
    ####delete I###
    ###############
    accept.I[m]=6
    
    if(length(N_I)>length(N_N)){ 
      
      #pick which house to delete
      update=sampleWithoutSurprises(N_I[!(N_I %in% N_N)])
      Istar[update] <- Inf
      check3[update] <- Inf
      tobs[update] <- maxt
      N_Istar<-N_I[which(N_I!=update)]
      trueremovaltime[update] = detectiontime[update] <- Inf
      bugstest <- bugs
      bugstest[update,] <- rep(0,maxt)
      logfirstpieceI <- log(firstpiece.wrap(I, beta[m], initialinfective, Rb[m], K, N, N_I, threshold))
      logfirstpieceI <- ifelse(logfirstpieceI=="-Inf",0,logfirstpieceI)
      loglike <- sum(logfirstpieceI)-secondpiece.wrap(I, trueremovaltime, beta[m], Rb[m], K, N, maxt, threshold,thresholdsum)
      logfirstpieceIstar<-log(firstpiece.wrap(Istar, beta[m], initialinfective, Rb[m], K, N, N_Istar, threshold))
      logfirstpieceIstar=ifelse(logfirstpieceIstar=="-Inf",0,logfirstpieceIstar)
      loglikestar <- sum(logfirstpieceIstar)-secondpiece.wrap(Istar, trueremovaltime, beta[m], Rb[m], K, N, maxt, threshold,thresholdsum)
      alpha.p <- 10*predprobs[update]
      beta.p <- 10 - alpha.p
      alpha.n <- 10*(totalnuminf+1)/N
      beta.n <- 10 - alpha.n
      bugsstar=rep(0,maxt)
      bugsstar[I[update]]=1
      lambda.bugsstar <- beverton.holt.update(K,Rb[m],bugsstar,trueremovaltime[update],I[update])[(I[update]):maxt]
      bugsstar <- bugs[update,(I[update]:maxt)]
      bugprior <- prod(dgamma(bugsstar, lambda.bugsstar, 1))
      probifnotdeleted <- (occult[update]+1)/m
      extra.piece <- (length(N_I)-length(N_N))/(length(which(I==Inf))+1)/dbeta(probifnotdeleted, alpha.p, beta.p)/dunif(update,min=1,max=length(which(I==Inf)))  
      #decide whether to accept new I
      mstep.I=min(1,exp(loglikestar-loglike)*extra.piece)
      if(mstep.I=="NaN") mstep.I=1
      R=runif(1)
      if(R<mstep.I){
        I<-Istar
        N_I<-N_I[which(N_I!=update)]
        accept.I[m] <- 5
        loglike <- loglikestar
        infectedhousesI[update]=0
        Q<-Qstar
        bugs<-bugstest
      }else{
        Istar<-I
        trueremovaltime[update]=maxt+1
        tobs[update]=maxt
        detectiontime[update]=Inf
        check3[update]=bugs[update,tobs[update]]}
      }
  }
  occult[N_I[!(N_I %in% N_N)]]=occult[N_I[!(N_I %in% N_N)]]+1
  occult.prob<- occult/m
  rank <- 1:N
  occult.prob.ids.unsorted <- cbind(id, occult.prob)
  occult.prob.ids <- occult.prob.ids.unsorted[order(occult.prob, decreasing = TRUE),]
  occult.prob.ids <- cbind(occult.prob.ids, rank)

}

return(list(occult.prob.ids.unsorted, beta, Rb, accept.I, accept.beta,accept.Rb,occults,N_N))
}




##################################################
####################################
S.sim=5 #number of simulations
p=1:10/1000
N=173
true.occult <- total <- neg <- rep(NA,S.sim)
total.prob=true.pos=true.neg=spec=sens=npv=ppv=matrix(NA,nrow=S.sim,ncol=length(p))
beta.sim=Rb.sim=accept.beta.sim=accept.Rb.sim=accept.I.sim=0
MLEbeta <- MLERb <- rep(NA, S.sim)

beta <- Rb <- matrix(0, nrow=S.sim,ncol=5)
acceptance <- matrix(0, nrow=S.sim, ncol=5)
occult.prob <- occultsforroc <- matrix(0, nrow=N, ncol=S.sim)


tic()

for (s in 1:S.sim){
  truebeta=0.3
  trueRb=2.1
  burnin=1
  
  sim <- runsimulation(truebeta,trueRb)
  data <- sim[[1]]
  occults <- sim[[2]]
  bugs <- sim[[3]]
  predprobs <- sim[[4]]
  threshold <- sim[[5]]
  blocks <- sim[[6]]
  distance <- sim[[7]]
  
  assign(paste("sim",s,sep=""),
         foreach(betastart=c(0.3,0.05,0.1), 
                 Rbstart=c(2.2, 2.7, 2.3), 
                 totaliterations=rep(5000000,3)) %do% {runMCMC(betastart, Rbstart, totaliterations,data, occults, bugs, predprobs, truebeta, trueRb, threshold, N, blocks, distance)})
  
  occult.prob.ids1 <- eval(as.name(paste("sim",s,sep="")))[[1]][[1]]
  occult.prob.ids2 <- eval(as.name(paste("sim",s,sep="")))[[2]][[1]]
  occult.prob.ids3 <- eval(as.name(paste("sim",s,sep="")))[[3]][[1]]
  occult.prob1 <- occult.prob.ids1[,2]
  occult.prob2 <- occult.prob.ids2[,2]
  occult.prob3 <- occult.prob.ids3[,2]
  occult.prob[,s] <- (occult.prob1+occult.prob2+occult.prob3)/3
  occults <- eval(as.name(paste("sim",s,sep="")))[[1]][[7]]
  occultsforroc[occults,s] <- 1
  N_N <- eval(as.name(paste("sim",s,sep="")))[[1]][[8]]
  beta.sim <- Rb.sim <- accept.I.sim <- accept.beta.sim <- accept.Rb.sim <- NULL
  
  for(i in 1:3) {
    betatemp <- eval(as.name(paste("sim",s,sep="")))[[i]][[2]]
    beta.sim <- c(beta.sim, betatemp[burnin:totaliterations])
    Rbtemp <- eval(as.name(paste("sim",s,sep="")))[[i]][[3]]
    Rb.sim <- c(Rb.sim, Rbtemp[burnin:totaliterations])
    accept.I <- eval(as.name(paste("sim",s,sep="")))[[i]][[4]]
    accept.I.sim <- c(accept.I.sim, accept.I[burnin:totaliterations])
    accept.beta <- eval(as.name(paste("sim",s,sep="")))[[i]][[5]]
    accept.beta.sim <- c(accept.beta.sim, accept.beta[burnin:totaliterations])
    accept.Rb <- eval(as.name(paste("sim",s,sep="")))[[i]][[6]]
    accept.Rb.sim <- c(accept.Rb.sim, accept.Rb[burnin:totaliterations])}
  
  beta[s,] <- quantile(beta.sim, c(0.025, 0.25, .5, .75, 0.975))
  Rb[s,] <- quantile(Rb.sim, c(0.025, 0.25, .5, .75, 0.975))
  acceptance[s,] <- c(mean(accept.beta.sim), mean(accept.Rb.sim), 
                      length(accept.I[which(accept.I==5)])/length(accept.I[which(accept.I==6|accept.I==5)]),
                      length(accept.I[which(accept.I==2)])/length(accept.I[which(accept.I==2|accept.I==3)]),
                      length(accept.I[which(accept.I==1)])/length(accept.I[which(accept.I==1|accept.I==0)])
  )
  
  #simulation statistics
  true.occult[s] <- length(occults)
  total[s] <- N-length(N_N)-1
  neg[s] <- total[s] - true.occult[s]
  
  for(i in seq(along=p)){
    total.prob[s,i]=length(occults[which(occult.prob>p[i])])
    true.pos[s,i]=length(which(which(occult.prob>p[i]) %in% occults))
    true.neg[s,i]=length(which(occult.prob<=p[i])) - length(which(which(occult.prob<=p[i]) %in% occults)) - length(N_N)-1
  }
  
  #calcuating conditions
  #sens=truly infected houses that we find / 
  npv[s,] <- true.neg[s,]/(total[s]-(total.prob[s,]-true.pos[s,]))
  sens[s,] <- true.pos[s,]/true.occult[s]
  ppv[s,] <- true.pos[s,]/total.prob[s,]
  spec[s,] <- true.neg[s,]/neg[s]}

}

toc()
