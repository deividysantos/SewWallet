-- CreateEnum
CREATE TYPE "AccountType" AS ENUM ('CHECKING', 'SAVINGS', 'WALLET', 'INVESTMENT', 'OTHER');

-- CreateEnum
CREATE TYPE "CategoryKind" AS ENUM ('INCOME', 'EXPENSE');

-- CreateEnum
CREATE TYPE "TransactionType" AS ENUM ('INCOME', 'EXPENSE', 'TRANSFER');

-- CreateEnum
CREATE TYPE "TransactionStatus" AS ENUM ('PENDING', 'PAID');

-- CreateEnum
CREATE TYPE "Frequency" AS ENUM ('WEEKLY', 'MONTHLY', 'YEARLY');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Account" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "AccountType" NOT NULL DEFAULT 'CHECKING',
    "initialBalance" INTEGER NOT NULL DEFAULT 0,
    "color" TEXT,
    "archived" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Account_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Category" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "kind" "CategoryKind" NOT NULL,
    "color" TEXT,
    "icon" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Category_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CreditCard" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "limit" INTEGER,
    "closingDay" INTEGER NOT NULL,
    "dueDay" INTEGER NOT NULL,
    "closingDayInNext" BOOLEAN NOT NULL DEFAULT true,
    "paymentAccountId" TEXT NOT NULL,
    "color" TEXT,
    "archived" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CreditCard_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Invoice" (
    "id" TEXT NOT NULL,
    "cardId" TEXT NOT NULL,
    "refMonth" DATE NOT NULL,
    "closingDate" DATE NOT NULL,
    "dueDate" DATE NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Invoice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Recurrence" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "frequency" "Frequency" NOT NULL,
    "interval" INTEGER NOT NULL DEFAULT 1,
    "startDate" DATE NOT NULL,
    "endDate" DATE,
    "generatedUntil" DATE NOT NULL,
    "type" "TransactionType" NOT NULL,
    "description" TEXT NOT NULL,
    "amount" INTEGER NOT NULL,
    "categoryId" TEXT,
    "accountId" TEXT,
    "toAccountId" TEXT,
    "cardId" TEXT,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Recurrence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Transaction" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "TransactionType" NOT NULL,
    "status" "TransactionStatus" NOT NULL DEFAULT 'PENDING',
    "description" TEXT NOT NULL,
    "amount" INTEGER NOT NULL,
    "date" DATE NOT NULL,
    "paidAt" DATE,
    "notes" TEXT,
    "categoryId" TEXT,
    "accountId" TEXT,
    "toAccountId" TEXT,
    "cardId" TEXT,
    "invoiceId" TEXT,
    "paysInvoiceId" TEXT,
    "installmentGroupId" TEXT,
    "installmentNumber" INTEGER,
    "installmentTotal" INTEGER,
    "recurrenceId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Transaction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- CreateIndex
CREATE INDEX "Account_userId_idx" ON "Account"("userId");

-- CreateIndex
CREATE INDEX "Category_userId_idx" ON "Category"("userId");

-- CreateIndex
CREATE INDEX "CreditCard_userId_idx" ON "CreditCard"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "Invoice_cardId_refMonth_key" ON "Invoice"("cardId", "refMonth");

-- CreateIndex
CREATE INDEX "Recurrence_userId_idx" ON "Recurrence"("userId");

-- CreateIndex
CREATE INDEX "Transaction_userId_date_idx" ON "Transaction"("userId", "date");

-- CreateIndex
CREATE INDEX "Transaction_invoiceId_idx" ON "Transaction"("invoiceId");

-- CreateIndex
CREATE INDEX "Transaction_paysInvoiceId_idx" ON "Transaction"("paysInvoiceId");

-- CreateIndex
CREATE INDEX "Transaction_recurrenceId_idx" ON "Transaction"("recurrenceId");

-- CreateIndex
CREATE INDEX "Transaction_installmentGroupId_idx" ON "Transaction"("installmentGroupId");

-- AddForeignKey
ALTER TABLE "Account" ADD CONSTRAINT "Account_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Category" ADD CONSTRAINT "Category_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CreditCard" ADD CONSTRAINT "CreditCard_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CreditCard" ADD CONSTRAINT "CreditCard_paymentAccountId_fkey" FOREIGN KEY ("paymentAccountId") REFERENCES "Account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Invoice" ADD CONSTRAINT "Invoice_cardId_fkey" FOREIGN KEY ("cardId") REFERENCES "CreditCard"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Recurrence" ADD CONSTRAINT "Recurrence_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "Account"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_toAccountId_fkey" FOREIGN KEY ("toAccountId") REFERENCES "Account"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_cardId_fkey" FOREIGN KEY ("cardId") REFERENCES "CreditCard"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "Invoice"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_paysInvoiceId_fkey" FOREIGN KEY ("paysInvoiceId") REFERENCES "Invoice"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_recurrenceId_fkey" FOREIGN KEY ("recurrenceId") REFERENCES "Recurrence"("id") ON DELETE SET NULL ON UPDATE CASCADE;
