
lag1CovSmootherLDS_SS <- function(Z, KN, B, Vnn, Jn, J0) {
    #SS16, Property 6.3
    M <- nrow(KN)
    N <- dim(Vnn)[3]
    Vnn1N <- array(NA, dim = c(M, M, N))
    eye <- diag(1, M)
    Vnn1N[, , N] <- (eye-KN%*%Z)%*%B%*%Vnn[,,N-1]
    for (k in N:3) {
        Vnn1N[,,k-1] <- Vnn[,,k-1]%*%t(Jn[,,k-2])+Jn[,,k-1]%*%(Vnn1N[,,k]-B%*%Vnn[,,k-1])%*%t(Jn[,,k-2])
    }
    Vnn1N[,,1] <- Vnn[,,1]%*%t(J0)+Jn[,,1]%*%(Vnn1N[,,2]-B%*%Vnn[,,1])%*%t(J0)
    return(Vnn1N)
}

checkCorrectnessOfCovsConstraints <- function(covsConstraints) {
    checkCorrectnessOfCovsConstraint <- function(covConstraint) {
        if(covConstraint!="unconstrained" && covConstraint!="diagonal and unequal") {
            stop(sprintf("Invalid covConstraint=%s\naccpeted values: unconstrained, diagonal and unequal", covConstraint))
        }
    }

    for(i in 1:length(covsConstraints)) {
        checkCorrectnessOfCovsConstraint(covConstraint=covsConstraints[[i]])
    }
}

emEstimationKF_SS_withOffsetsAndInputs <- function(y, c, d, B0, u0, C0, Q0, Z0, a0, D0, R0, m0, V0, maxIter=50, tol=1e-4, varsToEstimate=list(initialStateMean=TRUE, initialStateCovariance=TRUE, transitionMatrix=TRUE, transitionCovariance=TRUE, observationMatrix=TRUE, observationCovariance=TRUE), covsConstraints=list(V0="diagonal and unequal", Q="diagonal and unequal", R="diagonal and unequal")) {
    checkCorrectnessOfCovsConstraints(covsConstraints=covsConstraints)
    if(covsConstraints$V0=="diagonal and unequal") {
        nonDiagElems <- V0[col(V0)!=row(V0)]
        isDiag <- sum(nonDiagElems)==0
        if(!isDiag) {
            stop("V0 should be diagonal according to constraint")
        }
    }
    if(covsConstraints$Q=="diagonal and unequal") {
        nonDiagElems <- Q0[col(Q0)!=row(Q0)]
        isDiag <- sum(nonDiagElems)==0
        if(!isDiag) {
            stop("Q0 should be diagonal according to constraint")
        }
    }
    if(covsConstraints$R=="diagonal and unequal") {
        nonDiagElems <- R0[col(R0)!=row(R0)]
        isDiag <- sum(nonDiagElems)==0
        if(!isDiag) {
            stop("R0 should be diagonal according to constraint")
        }
    }
    B <- as.matrix(B0)
    u <- as.matrix(u0)
    # C <- as.matrix(C0)
    C <- C0
    Q <- as.matrix(Q0)
    Z <- as.matrix(Z0)
    a <- as.matrix(a0)
    # D <- as.matrix(D0)
    D <- D0
    R <- as.matrix(R0)
    m0 <- as.matrix(m0)
    V0 <- as.matrix(V0)

    M <- nrow(B0)
    N <- ncol(y)
    y <- as.matrix(y)
    # c <- as.matrix(c)
    # d <- as.matrix(d)
    cvg <- 1 + tol
    logLik <- matrix(0, maxIter, 1)
    for(iter in 1:maxIter) {
        kf <- filterLDS_SS_withOffsetsAndInputs(y=y, c=c, d=d, B=B, u=u, C=C, Q=Q, m0=m0, V0=V0, Z=Z, a=a, D=D, R=R)
        show(sprintf("LogLik[%04d]=%f", iter, kf$logLik))
        logLik[iter] <- kf$logLik
        if (iter > 1) {
            cvg <- (logLik[iter]-logLik[iter-1])/abs(logLik[iter])
        }
        if (cvg < 0) {
            warning("Likelihood Not Increasing")
            break
        }
        if (abs(cvg) < tol) {
            break
        }
        ks <- smoothLDS_SS(B=B, xnn=kf$xnn, Vnn=kf$Vnn, xnn1=kf$xnn1, Vnn1=kf$Vnn1, m0=m0, V0=V0)
        Vnn1N <- lag1CovSmootherLDS_SS(Z=Z, KN=kf$KN, B=B, Vnn=kf$Vnn, Jn=ks$Jn, J0=ks$J0)
        # begin compute summary statistics
        if(varsToEstimate$B || varsToEstimate$Q) {
            Sxx10 <- ks$xnN[,,1]%*%t(ks$x0N)+Vnn1N[,,1]
            Sxx00 <- ks$x0N%*%t(ks$x0N)+ks$V0N
        }
        if(varsToEstimate$Q || varsToEstimate$R || varsToEstimate$Z) {
            Sxx11 <- ks$xnN[,,1]%*%t(ks$xnN[,,1])+ks$VnN[,,1]
        }
        if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q)) {
            Sxc01 <- ks$x0N%*%t(c[,,1])
        }
        if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q)) {
            Sxc11 <- ks$xnN[,,1]%*%t(c[,,1])
        }
        if(varsToEstimate$R) {
            Syx11 <- y[,1]%*%t(ks$xnN[,,1])
            Syy11 <- y[,1]%*%t(y[,1])
        }
        if(!is.na(d[1]) && varsToEstimate$R) {
            Sxd11 <- ks$xnN[,,1]%*%t(d[,,1])
            Syd11 <- y[,1]%*%t(d[,,1])
        }
        if(varsToEstimate$Z) {
            if(!is.na(d[1])) {
                Symsx11 <- (y[,1]-a-D%*%d[,,1])%*%t(ks$xnN[,,1])
            } else {
                Symsx11 <- (y[,1]-a)%*%t(ks$xnN[,,1])
            }
        }
        if(!is.na(d[1]) && varsToEstimate$D) {
            Sy1d11 <- (y[,1]-Z%*%ks$xnN[,,1]-a)%*%t(d[,,1])
        }
        if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q)) {
            Scc11 <- c[,,1]%*%t(c[,,1])
        }
        if(!is.na(d[1]) && (varsToEstimate$D || varsToEstimate$R)) {
            Sdd11 <- d[,,1]%*%t(d[,,1])
        }
        #
        if(varsToEstimate$a || varsToEstimate$R) {
            Sy1 <- y[,1]
        }
        if(!is.na(d[1]) && (varsToEstimate$a || varsToEstimate$R)) {
            Sd1 <- d[,,1]
        }
        if(varsToEstimate$a || varsToEstimate$B || varsToEstimate$Q || varsToEstimate$R|| varsToEstimate$u ) {
            Sx1 <- ks$xnN[,,1]
        }
        if(varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q || varsToEstimate$u) {
            Sx0 <- ks$x0N
        }
        if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q || varsToEstimate$u)) {
            Sc1 <- c[,,1]
        }
        for (n in 2:N) {
            if(varsToEstimate$B || varsToEstimate$Q) {
                Sxx10 <- Sxx10+ks$xnN[,,n]%*%t(ks$xnN[,,n-1])+Vnn1N[,,n]
                Sxx00 <- Sxx00+ks$xnN[,,n-1]%*%t(ks$xnN[,,n-1])+ks$VnN[,,n-1]
            }
            if(varsToEstimate$Q || varsToEstimate$R || varsToEstimate$Z) {
                Sxx11 <- Sxx11+ks$xnN[,,n]%*%t(ks$xnN[,,n])+ks$VnN[,,n]
            }
            if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q)) {
                Sxc01 <- Sxc01+ks$xnN[,,n-1]%*%t(c[,,n])
            }
            if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q)) {
                Sxc11 <- Sxc11+ks$xnN[,,n]%*%t(c[,,n])
            }
            if(varsToEstimate$R) {
                Syx11 <- Syx11+y[,n]%*%t(ks$xnN[,,n])
                Syy11 <- Syy11+y[,n]%*%t(y[,n])
            }
            if(!is.na(d[1]) && (varsToEstimate$R)) {
                Sxd11 <- Sxd11+ks$xnN[,,n]%*%t(d[,,n])
                Syd11 <- Syd11+y[,n]%*%t(d[,,n])
            }
            if(varsToEstimate$Z) {
                if(!is.na(d[1])) {
                    Symsx11 <- Symsx11+(y[,n]-a-D%*%d[,,n])%*%t(ks$xnN[,,n])
                } else {
                    Symsx11 <- Symsx11+(y[,n]-a)%*%t(ks$xnN[,,n])
                }
            }
            if(!is.na(d[1]) && (varsToEstimate$D)) {
                Sy1d11 <- Sy1d11+(y[,n]-Z%*%ks$xnN[,,n]-a)%*%t(d[,,n])
            }
            if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q)) {
                Scc11 <- Scc11+c[,,n]%*%t(c[,,n])
            }
            if(!is.na(d[1]) && (varsToEstimate$D || varsToEstimate$R)) {
                Sdd11 <- Sdd11+d[,,n]%*%t(d[,,n])
            }
            #
            if(varsToEstimate$a || varsToEstimate$R) {
                Sy1 <- Sy1+y[,n]
            }
            if(!is.na(d[1]) && (varsToEstimate$a || varsToEstimate$R)) {
                Sd1 <- Sd1+d[,,n]
            }
            if(varsToEstimate$a || varsToEstimate$B || varsToEstimate$Q || varsToEstimate$R|| varsToEstimate$u ) {
                Sx1 <- Sx1+ks$xnN[,,n]
            }
            if(varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q || varsToEstimate$u) {
                Sx0 <- Sx0+ks$xnN[,,n-1]
            }
            if(!is.na(c[1]) && (varsToEstimate$B || varsToEstimate$C || varsToEstimate$Q || varsToEstimate$u)) {
                Sc1 <- Sc1+c[,,n]
            }
        }
        # end compute summary statistics

        # begin compute estimates
        if(varsToEstimate$B) {
            if(!is.na(c[1])) {
                commonFactor <- solve(Scc11-1/N*Sc1%*%t(Sc1))%*%(t(Sxc01)-1/N*Sc1%*%t(Sx0))
                num <- Sxx10-1/N*Sx1%*%t(Sx0)-(Sxc11-1/N*Sx1%*%t(Sc1))%*%commonFactor
                den <- Sxx00-1/N*Sx0%*%t(Sx0)-(Sxc01-1/N*Sx0%*%t(Sc1))%*%commonFactor
            } else {
                num <- Sxx10-1/N*Sx1%*%t(Sx0)
                den <- Sxx00-1/N*Sx0%*%t(Sx0)
            }
            B <- num%*%solve(den)
        }
        if(!is.na(c[1]) && varsToEstimate$C) {
            num <- Sxc11-B%*%Sxc01-1/N*(Sx1-B%*%Sx0)%*%t(Sc1)
            den <- Scc11-1/N*Sc1%*%t(Sc1)
            C <- num%*%solve(den)
        }
        if(varsToEstimate$u) {
            if(!is.na(c[1])) {
                u <- 1/N*(Sx1-B%*%Sx0-C%*%Sc1)
            } else {
                u <- 1/N*(Sx1-B%*%Sx0)
            }
        }
        if(varsToEstimate$Q) {
            Q <- Sxx11

            aux <- Sxx10%*%t(B)
            Q <- Q-(aux+t(aux))

            aux <- Sx1%*%t(u)
            Q <- Q-(aux+t(aux))

            Q <- Q+B%*%Sxx00%*%t(B)

            aux <- B%*%Sx0%*%t(u)
            Q <- Q+(aux+t(aux))

            Q <- Q+N*u%*%t(u)

            if(!is.na(c[1])) {
                aux <- Sxc11%*%t(C)
                Q <- Q-(aux+t(aux))

                aux <- B%*%Sxc01%*%t(C)
                Q <- Q+(aux+t(aux))

                aux <- u%*%Sc1%*%t(C)
                Q <- Q+(aux+t(aux))

                Q <- Q+C%*%Scc11%*%t(C)
            }

            Q <- Q/N

            Q <- (t(Q)+Q)/2

            if(covsConstraints$Q=="diagonal and unequal") {
                Q <- diag(diag(Q), nrow=nrow(Q)) # using the nrow argument to diag in case dim(Q)==c(1,1)
            }
        }
        if(varsToEstimate$Z) {
            Z <- Symsx11%*%solve(Sxx11)
        }
        if(!is.na(d[1]) && varsToEstimate$D) {
            D <- Sy1d11%*%solve(Sdd11)
        }
        if(varsToEstimate$a) {
            if(!is.na(d[1])) {
                a <- (Sy1-Z%*%Sx1-D%*%Sd1)/N
            } else {
                a <- (Sy1-Z%*%Sx1)/N
            }
        }
        if(varsToEstimate$R) {
            R <- Syy11

            aux <- Syx11%*%t(Z)
            R <- R-(aux+t(aux))

            aux <- Sy1%*%t(a)
            R <- R-(aux+t(aux))

            R <- R+Z%*%Sxx11%*%t(Z)

            aux <- Z%*%Sx1%*%t(a)
            R <- R+(aux+t(aux))

            R <- R+N*a%*%t(a)

            if(!is.na(d[1])) {
                aux <- Syd11%*%t(D)
                R <- R-(aux+t(aux))

                aux <- Z%*%Sxd11%*%t(D)
                R <- R+(aux+t(aux))

                aux <- a%*%Sd1%*%t(D)
                R <- R+(aux+t(aux))

                R <- R+D%*%Sdd11%*%t(D)
            }

            R <- R/N

            R <- (R+t(R))/2

            if(covsConstraints$R=="diagonal and unequal") {
                R <- diag(diag(R), nrow=nrow(R)) # using the nrow argument to diag in case dim(R)==c(1,1)
            }
        }
        if(varsToEstimate$m0) {
            m0 <- ks$x0N
        }
        if(varsToEstimate$V0) {
            V0 <- ks$V0N
            V0 <- (V0+t(V0))/2

            if(covsConstraints$V0=="diagonal and unequal") {
                V0 <- diag(diag(V0), nrow=nrow(V0)) # using the nrow argument to diag in case dim(V0)==c(1,1)
            }
        }
        # end compute estimates
    }
    answer <- list(B=B, u=u, C=C, Q=Q, Z=Z, a=a, D=D, R=R, m0=m0, V0=V0, xNN=ks$xnN[,,N], VNN=ks$VnN[,,N], logLik=logLik[1:iter], niter=iter, cvg=cvg, covsConstraints=covsConstraints)
    return(answer)
}
