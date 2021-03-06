##' Generate sample data from the hidden variable model.
##'
##' For further details see the references.
##' @title Hidden variable model
##' @param env integer vector of length n encoding to which experiment
##'   each repetition belongs.
##' @param L number of time points for evaluation.
##' @param par.noise list of parameters that specify the added
##'   noise. \code{noise.sd} specifies the standard deviation of
##'   noise, \code{only.target.noise} specifies whether to only add
##'   noise to target and \code{relative} specifies if the size of the
##'   noise should be relative to size of variable (if TRUE standard
##'   deviation is given by par.noise$noise.sd*(x(t)-x(t-1))).
##' @param intervention string specifying type of
##'   intervention. Currently three type of interventions are
##'   implemented "initial" (only intervene on intial values),
##'   "blockreactions" (intervene by blocking random reactions) or
##'   "intial_blockreactions" (intervene on both initial values and
##'   blockreactions").
##' @param intervention.par if intervention is either "blockreactions"
##'   or "initial_blockreactions", the rate constant k_7 is set to a
##'   noisy version of k_4. This parameter specifies size of this
##'   noise, more precisely k_7 is set to k_4 + \code{runif(1,
##'   -intervention.par, intervention.par)}.
##' @param hidden boolean whether the variables H1 and H2 should be
##'   removed from output.
##' @param ode.solver string specifying which ODE solver to use when
##'   solving ODE. Should be one of the methods from the
##'   \code{deSolve} package ("lsoda", "lsode", "lsodes", "lsodar",
##'   "vode", "daspk", "euler", "rk4", "ode23", "ode45", "radau",
##'   "bdf", "bdf_d", "adams", "impAdams", "impAdams_d", "iteration").
##' @param seed random seed. Does not work if a "Detected blow-up"
##'   warning shows up.
##' @param silent set to TRUE if no status output should be produced.
##' 
##' @return list consisting of the following elements
##' 
##' \item{simulated.data}{D-matrix of noisy data.}
##' \item{time}{vector containing time points}
##' \item{env}{vector specifying the experimental environment.}
##' \item{simulated.model}{object returned by ODE solver.}
##' \item{true.model}{vector specifying the target equation model.}
##' \item{target}{target variable.}
##' 
##' @export
##'
##' @import deSolve
##'
##' @author Niklas Pfister, Stefan Bauer and Jonas Peters
##'
##' @references
##' Pfister, N., S. Bauer, J. Peters (2018).
##' Identifying Causal Structure in Large-Scale Kinetic Systems
##' ArXiv e-prints (arXiv:1810.11776).
##'
##' @seealso The functions \code{\link{generate.data.maillard}} and
##'   \code{\link{generate.data.targetmodel}} allow to simulate ODE
##'   data from two additional models.
##'
##' @examples
##'
##' simulation.obj <- generate.data.hidden(env=rep(1:5, 3),
##'                                        L=15,
##'                                        par.noise=list(noise.sd=0.02,
##'                                                       only.target.noise=FALSE,
##'                                                       relativ=TRUE),
##'                                        intervention="initial_blockreactions",
##'                                        intervention.par=0.1)
##'
##' D <- simulation.obj$simulated.data
##' fulldata <- simulation.obj$simulated.model
##' time <- simulation.obj$time
##' plot(fulldata[[1]][,1], fulldata[[1]][,2], type= "l", lty=2,
##'      xlab="time", ylab="concentration")
##' points(time, D[1,1:length(time)], col="red", pch=19)
##' legend("topright", c("true trajectory", "observations"),
##'        col=c("black", "red"), lty=c(2, NA), pch=c(NA, 19))


generate.data.hidden <- function(env=rep(1,10),
                                 L=15,
                                 par.noise=list(noise.sd=0.01,
                                                only.target.noise=TRUE,
                                                relativ=FALSE),
                                 intervention="initial_blockreactions",
                                 intervention.par=0.1,
                                 hidden=TRUE,
                                 ode.solver="lsoda",
                                 seed=NA,
                                 silent=FALSE){
  # set seed
  if(is.numeric(seed)){
    set.seed(seed)
  }

  ###
  # Setting default parameters
  ###
  
  if(!exists("noise.sd",par.noise)){
    par.noise$noise.sd <- 0.01
  }
  if(!exists("only.target.noise",par.noise)){
    par.noise$only.target.noise <- TRUE
  }
  if(!exists("target",par.noise)){
    par.noise$target <- 1
  }
  if(!exists("relativ",par.noise)){
    par.noise$relativ <- FALSE
  }

  
  ######################################
  #
  # Simulate data
  #
  ######################################
  
  
  ###
  # Initialize RHS
  ###

  reactions <- function(t, x, theta){
    
    dx1 <- theta[3]*x[7] - theta[1]*x[1] - theta[6]*x[1]*x[4]
    dx2 <- theta[2]*x[7] - theta[7]*x[2]
    dx3 <- theta[6]*x[1]*x[4] - theta[5]*x[3] + theta[8]*x[5]
    dx4 <- theta[5]*x[3] - theta[6]*x[1]*x[4] - theta[9]*x[4]
    dx5 <- theta[9]*x[4] - theta[8]*x[5]
    dx6 <- theta[7]*x[2]
    dx7 <- theta[1]*x[1] - (theta[2]+theta[3])*x[7]
    dx8 <- theta[2]*x[7] - theta[4]*x[8]
    dx9 <- theta[4]*x[8] + theta[5]*x[3]
    
    return(list(c(dx1,dx2,dx3,dx4,dx5,dx6,dx7,dx8,dx9)))
  }

  
  ###
  # Set parameters
  ###
  
  d <- 9
  target <- 9
  time.grid <- seq(0, 100, by=0.005)
  time.index <- c(1, floor(exp(seq(1, log(length(time.grid)), length.out=(L-1)))))
  initial_obs <- c(5, 0, 0, 5, 0, 0, 0, 0, 0)
  theta_obs <- c(0.8, 0.8, 0.1, 1, 0.03, 0.6, 1, 0.2, 0.5)*0.1
  n.env <- length(unique(env))
  
  true_set <- c(list(3))
 
  ###
  # Define interventions
  ###
  
  if(intervention == "initial"){
    intervention_fun <- function(){
      initial_int <- c(runif(1, 0, 10), 0, 0, runif(1, 0, 10), runif(1, 0, 10), 0, 0, 0, 0)
      return(list(initial=initial_int,
                  theta=theta_obs))
    }
  }
  else if(intervention == "blockreactions"){
    true_set <- c(list(3))
    fixed_reactions <- c(4, 5, 7)
    intervention_fun <- function(){
      r_vec <- (1:length(theta_obs))[-fixed_reactions]
      num_reactions <- length(r_vec)
      theta_int <- theta_obs
      theta_int[r_vec] <- theta_int[r_vec]*rbinom(num_reactions, 1, 1-1/num_reactions)
      theta_int[7] <- max(c(theta_obs[7] + runif(1, -intervention.par, intervention.par),0))
      return(list(initial=initial_obs,
                  theta=theta_int))
    }
  }
  else if(intervention == "initial_blockreactions"){
    true_set <- c(list(3))
    fixed_reactions <- c(4, 5, 7)
    intervention_fun <- function(){
      r_vec <- (1:length(theta_obs))[-fixed_reactions]
      num_reactions <- length(r_vec)
      theta_int <- theta_obs
      theta_int[r_vec] <- theta_int[r_vec]*rbinom(num_reactions, 1, 1-1/num_reactions)
      theta_int[7] <- max(c(theta_obs[7] + runif(1, -intervention.par, intervention.par),0))
      initial_int <- c(runif(1, 0, 10), 0, 0,
                       runif(1, 0, 10), runif(1, 0, 10), 0, 0, 0, 0)
      return(list(initial=initial_int,
                  theta=theta_int))
    }
  }
  else{
    stop("Specified intervention does not exist")
  }


  ###
  # Generate data from exact ODE and generate observations
  ###
  
  # set up required variables
  simulated.data <- matrix(NA, length(env), L*d)
  simulated.model <- vector("list", n.env)
  time <- time.grid[time.index]
  
  # iterate over environments
  for(i in 1:n.env){
    env.size <- sum(env == i)
    # perform intervention: initial condition
    if(i == 1){
      initial <- initial_obs
      theta <- theta_obs
    }
    else{
      int_data <- intervention_fun()
      initial <- int_data$initial
      theta <- int_data$theta
    }
    
    # solve ODE numerically
    if(!silent){
      print(paste("Currently solving ODE-system on environment", i))
    }
    
    # catch warnings from ODE solver --> not a good model
    simulated.model[[i]] <- ode(initial, time.grid, reactions, theta, method=ode.solver)
    if(!is.numeric(simulated.model[[i]]) | nrow(simulated.model[[i]])<length(time.grid)){
      if(!silent){
        print("Problem in ode-solver")
      }
      return(NA)
    }
    
    # select time points and add noise
    if(par.noise$only.target.noise){
      target.ind <- ((target-1)*L+1):(target*L)
      tmp <- simulated.model[[i]][time.index, -1, drop=FALSE]
      if(par.noise$relativ){
        noise_var <- par.noise$noise.sd*diff(range(tmp[, target]))+0.0000001
        noiseterm <- matrix(rnorm(L*env.size, 0, noise_var), env.size, L)
      }
      else{
        noiseterm <- matrix(rnorm(L*env.size, 0, par.noise$noise.sd), env.size, L)
      }
      simulated.data[env==i, ] <- matrix(rep(tmp, env.size), env.size, L*d, byrow=TRUE)
      simulated.data[env==i, target.ind] <- simulated.data[env==i, target.ind] + noiseterm
    }
    else{
      tmp <- simulated.model[[i]][time.index, -1]
      if(par.noise$relativ){
        noise_var <- apply(tmp, 2, function(x) par.noise$noise.sd*diff(range(x)))+0.0000001
        noiseterm <- matrix(rnorm(L*d*env.size, 0, rep(rep(noise_var, each=L), env.size)), env.size, L*d, byrow=TRUE)
      }
      else{
        noiseterm <- matrix(rnorm(L*d*env.size, 0, par.noise$noise.sd), env.size, L*d)
      }
      simulated.data[env==i,] <-  matrix(rep(tmp, env.size), env.size, L*d, byrow=TRUE) + noiseterm
    }
  }

  ###
  # Check if a blow-up occured
  ###

  blowup <- vector("logical", n.env)
  for(i in 1:n.env){
    blowup[i] <- sum(abs(simulated.model[[i]][length(time.grid),-1])>10^8 |
                       is.na(abs(simulated.model[[i]][length(time.grid),-1])))>0
  }
  if(sum(blowup)>0){
    if(!silent){
      print("Detected blow-up")
    }

    ## Call function again (no seed!)
    res <- generate.data.hidden(env=env,
                                L=L,
                                par.noise=par.noise,
                                intervention=intervention,
                                hidden=hidden,
                                ode.solver=ode.solver,
                                seed=NA,
                                silent=silent)
    return(res)
  }

  ###
  # Remove hidden variables
  ###
  
  if(hidden){
    hidden_index <- (6*L+1):(8*L)
    simulated.data <- simulated.data[,-hidden_index]
    target <- 7
  }
  else{
    target <- 9
  }

  return(list(simulated.data=simulated.data,
              time=time,
              env=env,
              simulated.model=simulated.model,
              true.model=true_set,
              target=target))
}
