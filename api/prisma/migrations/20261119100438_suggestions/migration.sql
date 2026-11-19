-- CreateEnum
CREATE TYPE "SuggestionStatus" AS ENUM ('PENDING', 'ACCEPTED', 'DISMISSED', 'AUTO_PAID', 'ALREADY_EXISTS', 'IGNORED', 'ERROR');

-- AlterTable
ALTER TABLE "CreditCard" ADD COLUMN     "lastDigits" TEXT;

-- CreateTable
CREATE TABLE "Suggestion" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "SuggestionStatus" NOT NULL,
    "reason" TEXT,
    "app" TEXT NOT NULL,
    "appName" TEXT,
    "title" TEXT,
    "text" TEXT NOT NULL,
    "postedAt" TIMESTAMP(3) NOT NULL,
    "hash" TEXT NOT NULL,
    "type" "TransactionType",
    "channel" TEXT,
    "amount" INTEGER,
    "date" DATE,
    "merchant" TEXT,
    "description" TEXT,
    "accountId" TEXT,
    "cardId" TEXT,
    "categoryId" TEXT,
    "installments" INTEGER,
    "confidence" DOUBLE PRECISION,
    "transactionId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Suggestion_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Suggestion_userId_status_idx" ON "Suggestion"("userId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "Suggestion_userId_hash_key" ON "Suggestion"("userId", "hash");

-- AddForeignKey
ALTER TABLE "Suggestion" ADD CONSTRAINT "Suggestion_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

